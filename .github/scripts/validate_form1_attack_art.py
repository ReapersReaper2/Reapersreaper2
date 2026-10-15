#!/usr/bin/env python3
"""Validate exactly the 20 NEW-CANON Mollosar Form 1 sword-attack strips.

Usage: python3 .github/scripts/validate_form1_attack_art.py [--require-approved]
If the approved manifest does not yet exist, CI's default mode leaves gameplay
on the existing fallback. For delivery use --require-approved to reject absence.
This is structural and alpha QA: it does NOT substitute for visual art approval.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path

ACTIONS = ('windup', 'slash', 'rslash', 'heavy', 'recover')
DIRECTIONS = ('front', 'back', 'side-l', 'side-r')
CELL = 384
FPS = 12.0
ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / 'godot-project/sprites/mollosar/approved'
MANIFEST = ART / 'form1_attack_manifest.json'


def validate(require: bool = False) -> list[str]:
    errors = []
    if not MANIFEST.is_file():
        if require:
            return ['Missing approved Form 1 attack manifest; 20 strips are required']
        print('[FORM1 ART] SKIP: complete 20-strip asset set not installed (procedural fallback remains)')
        return []
    try:
        m = json.loads(MANIFEST.read_text('utf-8'))
    except (OSError, json.JSONDecodeError) as exc:
        return [f'Malformed manifest: {exc}']
    if m.get('status') != 'APPROVED':
        errors.append('Manifest status must be APPROVED')
    entries = m.get('strips')
    expected = {f'{a}_{d}' for a in ACTIONS for d in DIRECTIONS}
    if not isinstance(entries, dict):
        return errors + ['Manifest strips must be an object']
    if entries.keys() != expected:
        errors.append('Expected exactly 20 clips; missing=' + str(sorted(expected - entries.keys())) +
                      ' extra=' + str(sorted(entries.keys() - expected)))

    # Optional dependencies are needed only when an approved set is installed.
    # Empty-asset CI builds must still validate the procedural fallback without pip.
    from PIL import Image
    import numpy as np
    total_frames = 0
    for action in ACTIONS:
        for direction in DIRECTIONS:
            key = f'{action}_{direction}'
            item = entries.get(key)
            if not isinstance(item, dict):
                continue
            num = 8 if action == 'heavy' else 6
            expected_path = f'res://sprites/mollosar/approved/form1_{key}.png'
            if item.get('texture') != expected_path:
                errors.append(f'{key}: texture must be {expected_path}')
            if item.get('frames') != num or item.get('cell') != [CELL, CELL] or abs(float(item.get('fps') or 0)-FPS) > .01:
                errors.append(f'{key}: expected {num} frames, 384px cells, 12fps')
            pivot = item.get('pivot')
            if not isinstance(pivot, list) or len(pivot) != 2 or not (0 <= pivot[0] <= CELL and 0 <= pivot[1] <= CELL):
                errors.append(f'{key}: invalid pivot')
            path = ART / f'form1_{key}.png'
            if not path.is_file():
                errors.append(f'{key}: missing PNG')
                continue
            try:
                with Image.open(path) as im:
                    if im.format != 'PNG' or im.mode != 'RGBA':
                        errors.append(f'{key}: must be an RGBA PNG')
                    if im.size != (num*CELL, CELL):
                        errors.append(f'{key}: expected {num*CELL}x384, got {im.size}')
                        continue
                    pixels = np.asarray(im.convert('RGBA'))
            except Exception as exc:
                errors.append(f'{key}: cannot decode PNG: {exc}')
                continue
            alpha = pixels[:,:,3]
            other = np.count_nonzero((alpha != 0) & (alpha != 255))
            if other:
                errors.append(f'{key}: {other:,} semi-transparent pixels; expected only 0 or 255')
            hashes = set()
            for f in range(num):
                cell = pixels[:,f*CELL:(f+1)*CELL]
                mask = cell[:,:,3] == 255
                coverage = float(mask.mean())
                if coverage < 0.075 or coverage > 0.86:
                    errors.append(f'{key} frame {f}: painted coverage {coverage:.1%} outside 7.5-86%')
                positions = np.argwhere(mask)
                if positions.size:
                    mn = positions.min(axis=0)
                    mx = positions.max(axis=0)
                    if min(mn[0], mn[1], CELL-1-mx[0], CELL-1-mx[1]) < 2:
                        errors.append(f'{key} frame {f}: art touches cell edges (clipping risk)')
                hashes.add(hashlib.sha256(cell.tobytes()).digest())
            if len(hashes) < num:
                errors.append(f'{key}: identical frames detected; all {num} frames must be individually animated')
            total_frames += num
    if total_frames != 128:
        errors.append(f'Loaded {total_frames}/128 expected frames')
    return errors


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument('--require-approved',action='store_true')
    args = p.parse_args()
    errs = validate(args.require_approved)
    for error in errs:
        print('ERROR:', error)
    if errs:
        print(f'[FORM1 ART] FAIL: {len(errs)} errors; do not ship these assets')
        return 1
    print('[FORM1 ART] Structural checks passed; artist review is still required')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
