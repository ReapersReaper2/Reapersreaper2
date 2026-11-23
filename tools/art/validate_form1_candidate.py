#!/usr/bin/env python3
"""Fail-closed technical intake for a NON-PRODUCTION Form 1 animation candidate.

This does not approve art. Example:
 python tools/art/validate_form1_candidate.py path/to/slash_side-r.png --action slash
"""
from __future__ import annotations
import argparse
from pathlib import Path
from PIL import Image

CELL = 384
ALLOWED_ACTIONS = {"windup": 6, "slash": 6, "rslash": 6,
                   "recover": 6, "heavy": 8}


def validate(path: Path, action: str) -> tuple[list[str], list[str]]:
    errors, warnings = [], []
    if action not in ALLOWED_ACTIONS:
        return [f"Unknown action: {action}"], []
    if not path.is_file():
        return [f"File not found: {path}"], []
    try:
        with Image.open(path) as source:
            source.load()
            size = source.size
            mode = source.mode
            file_format = source.format
            if mode == "RGBA":
                alpha = source.getchannel("A")
            else:
                alpha = None
    except Exception as exc:
        return [f"Unable to decode candidate: {exc}"], []
    frames = ALLOWED_ACTIONS[action]
    expected = (CELL * frames, CELL)
    if size != expected:
        errors.append(f"Invalid size {size}; expected {expected} for {frames} 384px cells")
    if file_format != "PNG":
        errors.append(f"Expected PNG, got {file_format}")
    if mode != "RGBA" or alpha is None:
        errors.append(f"Expected true RGBA image, got {mode}")
        return errors, warnings
    hist = alpha.histogram()
    semitransparent = sum(hist[1:255])
    if semitransparent:
        errors.append(f"{semitransparent} pixels have nonbinary alpha")
    if hist[0] == 0:
        errors.append("No transparent pixels: likely opaque background")
    if size == expected:
        for i in range(frames):
            mask = alpha.crop((i * CELL, 0, (i + 1) * CELL, CELL))
            bbox = mask.getbbox()
            if bbox is None:
                errors.append(f"Frame {i}: empty image")
                continue
            left, top, right, bottom = bbox
            if left == 0 or right == CELL or top == 0 or bottom == CELL:
                warnings.append(f"Frame {i}: nontransparent pixels touch cell boundary")
            # Approved Form 1 sprite geometry pins the soles near y=376.
            if bottom < 360:
                warnings.append(f"Frame {i}: lowest painted pixel at y={bottom-1}; verify foot pivot [192,376]")
            if right - left < 80 or bottom - top < 200:
                warnings.append(f"Frame {i}: unusually small painted silhouette {bbox}")
    return errors, warnings


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("path", type=Path)
    p.add_argument("--action", choices=sorted(ALLOWED_ACTIONS), default="slash")
    args = p.parse_args()
    errors, warnings = validate(args.path, args.action)
    for warning in warnings:
        print("WARNING:", warning)
    for error in errors:
        print("ERROR:", error)
    print(f"Candidate intake: {'FAIL' if errors else 'PASS TECHNICAL ONLY'}"
          f"; {len(errors)} errors, {len(warnings)} warnings")
    raise SystemExit(1 if errors else 0)


if __name__ == "__main__":
    main()
