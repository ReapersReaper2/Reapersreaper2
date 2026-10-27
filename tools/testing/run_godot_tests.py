"""Bounded Godot 4.3 baseline and real-render capture; standard library only."""
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

ERROR = re.compile(r"(?im)^\s*(?:SCRIPT ERROR:|ERROR:|FAIL(?:ED)?\b)|\bALL FAIL\b")


def run(exe, args, out, name, timeout, env):
    start = time.monotonic()
    command = [str(exe), *map(str, args)]
    timed_out = False
    with (out / f"{name}.stdout.txt").open("w", encoding="utf-8") as stdout, (out / f"{name}.stderr.txt").open("w", encoding="utf-8") as stderr:
        process = subprocess.Popen(command, stdout=stdout, stderr=stderr, env=env)
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            if os.name == "nt":
                subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], capture_output=True)
            process.kill()
            process.wait()
            code = -1
    raw = "\n".join((out / f"{name}.{stream}.txt").read_text(encoding="utf-8", errors="replace") for stream in ("stdout", "stderr"))
    (out / f"{name}.log").write_text(raw, encoding="utf-8")
    errors = len(ERROR.findall(raw))
    result = dict(test=name, exit_code=code, timed_out=timed_out, engine_errors=errors,
                  result="PASS" if code == 0 and not timed_out and errors == 0 else "FAIL",
                  seconds=round(time.monotonic() - start, 2), command=command)
    print(f"{result['result']}: {name} ({result['seconds']}s, errors={errors})", flush=True)
    return result, raw


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[2] / "godot-project")
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument("--capture", action="store_true")
    a = parser.parse_args()
    a.godot = a.godot.resolve()
    a.project = a.project.resolve()
    out = a.output.resolve()
    # Never reuse stale evidence or the owner's save directory.
    out.mkdir(parents=True, exist_ok=False)
    env = os.environ.copy()
    for key in ("APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME"):
        directory = out / "userdata" / key
        directory.mkdir(parents=True)
        env[key] = str(directory)
    results = []
    manifest = dict(mode="capture" if a.capture else "baseline", started_utc=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                    os=sys.platform, project=str(a.project), status="INCOMPLETE")
    try:
        manifest["commit"] = subprocess.check_output(["git", "-C", str(a.project), "rev-parse", "HEAD"], text=True).strip()
        manifest["worktree_status"] = subprocess.check_output(["git", "-C", str(a.project), "status", "--porcelain"], text=True)
        version, text = run(a.godot, ["--version"], out, "version", 30, env)
        results.append(version)
        manifest["godot"] = text.strip()
        if version["result"] != "PASS" or not re.search(r"^4\.3\.stable\.official\.77dcf97d8\s*$", text.strip()):
            raise RuntimeError("Expected official Godot 4.3 stable (77dcf97d8)")
        imported, _ = run(a.godot, ["--headless", "--path", a.project, "--import"], out, "import", 600, env)
        results.append(imported)
        if imported["result"] != "PASS":
            raise RuntimeError("Import failed; tests/capture not executed")
        if a.capture:
            # Probe graphics independently so game errors cannot masquerade as unsupported hardware.
            probe = out / "probe"
            probe.mkdir()
            (probe / "project.godot").write_text('config_version=5\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
            (probe / "probe.gd").write_text('extends SceneTree\nfunc _initialize():\n\tcall_deferred("capture")\nfunc capture():\n\troot.size = Vector2i(320, 180)\n\tawait RenderingServer.frame_post_draw\n\tvar image = root.get_texture().get_image()\n\tif image == null or image.is_empty():\n\t\tquit(1)\n\t\treturn\n\tvar err = image.save_png("res://probe.png")\n\tprint("GRAPHICS_PROBE_OK" if err == OK else "GRAPHICS_PROBE_FAILED")\n\tquit(0 if err == OK else 1)\n')
            result, text = run(a.godot, ["--path", probe, "--audio-driver", "Dummy", "--script", "res://probe.gd"], out, "graphics-probe", 45, env)
            manifest["graphics_probe"] = result
            if result["result"] != "PASS" or "GRAPHICS_PROBE_OK" not in text or not (probe / "probe.png").exists():
                manifest["status"] = "UNSUPPORTED_GRAPHICS"
                return 0
            capture_dir = out / "frames"
            capture_dir.mkdir()
            result, text = run(a.godot, ["--path", a.project, "--audio-driver", "Dummy", "--resolution", "1280x720", "--fixed-fps", "60", "--script", "res://scripts/rebirth_gameplay_capture.gd", "--", str(capture_dir)], out, "gameplay-capture", 180, env)
            manifest["captured_frames"] = len(list(capture_dir.glob("*.png")))
            manifest["capture_completed"] = "REBIRTH_CAPTURE_COMPLETE" in text and manifest["captured_frames"] == 27
            if not manifest["capture_completed"]:
                result["result"] = "FAIL"
            results.append(result)
        else:
            tests = sorted((a.project / "scripts").glob("*_test.gd"))
            if not tests:
                raise RuntimeError("No tests discovered")
            manifest["test_roster"] = [p.name for p in tests]
            for test in tests:
                result, _ = run(a.godot, ["--headless", "--path", a.project, "--script", "res://scripts/" + test.name], out, test.stem, a.timeout, env)
                results.append(result)
                (out / "results.json").write_text(json.dumps(results, indent=2))
        manifest["status"] = "PASS" if all(r["result"] == "PASS" for r in results) else "FAIL"
        return 0 if manifest["status"] == "PASS" else 1
    except Exception as exc:
        manifest["status"] = "FAIL"
        manifest["error"] = str(exc)
        print(str(exc), file=sys.stderr)
        return 1
    finally:
        manifest["results"] = results
        with (out / "results.csv").open("w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=["test", "result", "exit_code", "timed_out", "engine_errors", "seconds"], extrasaction="ignore")
            writer.writeheader()
            writer.writerows(results)
        manifest["evidence_sha256"] = {str(p.relative_to(out)): hashlib.sha256(p.read_bytes()).hexdigest() for p in out.rglob("*") if p.is_file() and "userdata" not in p.parts and p.name != "manifest.json"}
        (out / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
        print(f"Evidence: {out}; status: {manifest['status']}")


if __name__ == "__main__":
    sys.exit(main())
