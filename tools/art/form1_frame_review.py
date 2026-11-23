#!/usr/bin/env python3
"""Non-destructive visual intake for Mollosar's approved Form 1 strips.

Writes diagnostic crops, contact sheets, and a CSV. This does not fix or approve
art: separate opaque islands can be legitimate sword effects/hair strands.
Usage:
 python tools/art/form1_frame_review.py --clip slash_side-r --output evidence/form1
 python tools/art/form1_frame_review.py --clip all --output evidence/form1
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
from collections import deque
from pathlib import Path

from PIL import Image, ImageDraw

PROJECT = Path(__file__).resolve().parents[2] / "godot-project"
MANIFEST = PROJECT / "sprites/mollosar/approved/form1_attack_manifest.json"


def islands(mask: Image.Image, min_pixels: int = 8) -> list[tuple[int, tuple[int, int, int, int]]]:
    """4-connected alpha islands; returns pixel count and inclusive bbox."""
    width, height = mask.size
    data = mask.load()
    visited = bytearray(width * height)
    found = []
    for y in range(height):
        for x in range(width):
            pos = y * width + x
            if visited[pos] or not data[x, y]:
                continue
            visited[pos] = 1
            pending = deque([(x, y)])
            count, xmin, xmax, ymin, ymax = 0, x, x, y, y
            while pending:
                px, py = pending.popleft()
                count += 1
                xmin, xmax = min(xmin, px), max(xmax, px)
                ymin, ymax = min(ymin, py), max(ymax, py)
                for nx, ny in ((px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)):
                    if 0 <= nx < width and 0 <= ny < height:
                        ni = ny * width + nx
                        if not visited[ni] and data[nx, ny]:
                            visited[ni] = 1
                            pending.append((nx, ny))
            if count >= min_pixels:
                found.append((count, (xmin, ymin, xmax, ymax)))
    return sorted(found, reverse=True)


def inspect_frame(frame: Image.Image) -> dict:
    alpha = frame.getchannel("A")
    mask = alpha.point(lambda p: 255 if p > 0 else 0)
    bbox = mask.getbbox()  # exclusive max coordinates
    edge = any(
        alpha.getpixel((x, y)) > 0
        for x in range(frame.width)
        for y in (0, frame.height - 1)
    ) or any(
        alpha.getpixel((x, y)) > 0
        for y in range(frame.height)
        for x in (0, frame.width - 1)
    )
    components = islands(mask)
    return {
        "bbox": "" if bbox is None else ",".join(map(str, bbox)),
        "edge_touch": edge,
        "islands_ge8": len(components),
        "largest_island_px": components[0][0] if components else 0,
        "small_islands": "; ".join(f"{size}@{box}" for size, box in components[1:8]),
        "alpha_binary": alpha.getextrema() in ((0, 0), (255, 255), (0, 255))
        and all(a in (0, 255) for _, a in alpha.getcolors(maxcolors=frame.width * frame.height) or []),
    }


def checker_cell(frame: Image.Image, label: str) -> Image.Image:
    w, h = frame.size
    canvas = Image.new("RGB", (w, h + 28), "#25272e")
    d = ImageDraw.Draw(canvas)
    for yy in range(0, h, 16):
        for xx in range(0, w, 16):
            d.rectangle((xx, yy, min(xx + 15, w - 1), min(yy + 15, h - 1)),
                        fill="#454952" if (xx // 16 + yy // 16) % 2 else "#34383f")
    canvas.paste(frame, (0, 0), frame)
    d.text((10, h + 7), label, fill="white")
    return canvas


def review(manifest: Path, clip: str, out: Path) -> list[dict]:
    data = json.loads(manifest.read_text(encoding="utf-8"))
    if data.get("status") != "APPROVED":
        raise ValueError("Manifest not approved; review source selection")
    entries = data["strips"]
    selected = sorted(entries) if clip == "all" else [clip]
    out.mkdir(parents=True, exist_ok=True)
    rows = []
    for name in selected:
        if name not in entries:
            raise ValueError(f"Unknown clip {name!r}; available: {', '.join(sorted(entries))}")
        entry = entries[name]
        frames, (cw, ch) = int(entry["frames"]), entry["cell"]
        texture = entry["texture"]
        if not texture.startswith("res://") or ".." in texture:
            raise ValueError(f"Unsafe resource path for {name}")
        path = manifest.parents[2] / texture.removeprefix("res://")
        # manifest lives in godot-project/sprites/mollosar/approved;
        # parents[2] is godot-project.
        if not path.is_file():
            raise FileNotFoundError(path)
        source_hash = hashlib.sha256(path.read_bytes()).hexdigest()
        with Image.open(path) as original:
            image = original.convert("RGBA")
        if image.size != (frames * cw, ch):
            raise ValueError(f"{name}: got {image.size}, expected {(frames * cw, ch)}")
        clip_dir = out / name
        clip_dir.mkdir(exist_ok=True)
        contact = Image.new("RGB", (cw * frames, ch + 28), "#20232a")
        for index in range(frames):
            frame = image.crop((index * cw, 0, (index + 1) * cw, ch))
            frame.save(clip_dir / f"frame_{index:02d}.png")
            metrics = inspect_frame(frame)
            rows.append({"clip": name, "frame_zero_based": index,
                         "source_sha256": source_hash, **metrics})
            contact.paste(checker_cell(frame, f"{name} / frame {index}"), (index * cw, 0))
        contact.save(clip_dir / "contact.png")
    if rows:
        with (out / "frame_diagnostics.csv").open("w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            writer.writeheader()
            writer.writerows(rows)
    (out / "README.txt").write_text(
        "VISUAL TRIAGE ONLY. Edge touches and detached alpha islands are clues, not "
        "automatic defects. Review character anatomy, blade continuity and "
        "approved canon by eye. Originals unchanged. Zero-based frame indices.\n",
        encoding="utf-8")
    return rows


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clip", default="slash_side-r",
                        help="Manifest clip key (default slash_side-r), or all")
    parser.add_argument("--output", type=Path, default=Path("evidence/form1"))
    parser.add_argument("--manifest", type=Path, default=MANIFEST)
    args = parser.parse_args()
    rows = review(args.manifest, args.clip, args.output)
    print(f"Inspected {len(rows)} source frames; evidence: {args.output.resolve()}")
    print(f"Edge-touch candidates: {sum(r['edge_touch'] for r in rows)}")
    print("No source art or manifest was modified.")


if __name__ == "__main__":
    main()
