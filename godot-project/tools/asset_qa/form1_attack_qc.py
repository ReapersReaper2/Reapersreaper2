#!/usr/bin/env python3
"""Validate Muse Form 1 384px RGBA strips. Requires Pillow."""
import argparse
import json
from pathlib import Path
from PIL import Image

DIRECTIONS = ("down", "up", "left", "right")
MOTIONS = ("slash", "return", "windup", "heavy", "recover")

def inspect(path, reference=False):
    errors = []
    if not path.is_file():
        return {"ok": False, "errors": ["missing PNG"]}
    try:
        with Image.open(path) as image:
            if image.mode != "RGBA":
                errors.append("requires real RGBA, not opaque RGB")
            width, height = image.size
            if height != 384 or width % 384:
                return {"ok": False, "errors": errors + ["invalid 384px grid"]}
            frames = width // 384
            if frames != 4 if reference else not 6 <= frames <= 8:
                errors.append("incorrect frame count")
            for i in range(frames):
                frame = image.crop((384*i, 0, 384*(i+1), 384)).convert("RGBA")
                alpha = frame.getchannel("A")
                hist = alpha.histogram()
                if sum(hist[:5]) < 10000:
                    errors.append(f"frame {i}: opaque background")
                if not reference:
                    foot = alpha.crop((118,315,268,384)).point(
                        lambda v: 255 if v >= 128 else 0).getbbox()
                    if foot is None or abs(foot[3]+314-372)>7:
                        errors.append(f"frame {i}: unstable foot baseline")
    except (OSError, ValueError) as exc:
        errors.append(str(exc))
    return {"ok": not errors, "errors": errors}

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--references", type=Path, required=True)
    p.add_argument("--candidates", type=Path)
    p.add_argument("--out", type=Path, required=True)
    args = p.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    results = {}
    for direction in DIRECTIONS:
        name = f"form1_walk_{direction}_spec384.png"
        results[name] = inspect(args.references/name, True)
    if args.candidates:
        for motion in MOTIONS:
            for direction in DIRECTIONS:
                name = f"form1_attack_{motion}_{direction}_spec384.png"
                results[name] = inspect(args.candidates/name)
    (args.out/"form1_attack_qc_report.json").write_text(
        json.dumps(results, indent=2)+"\n")
    failures = [name for name,r in results.items() if not r["ok"]]
    print(f"Form 1 QA: {len(results)-len(failures)}/{len(results)} PASS")
    raise SystemExit(bool(failures))

if __name__ == "__main__":
    main()
