#!/usr/bin/env python3
"""Restore exact, existing approved PNG bytes when Git LFS gives pointer stubs.

This never invents or modifies art. Critical .b64 masters already ship in the
repository as exact source copies, and are needed for reliable Android export.
An actual valid PNG checkout always wins.
"""
from __future__ import annotations

import base64
from pathlib import Path
import struct
import sys

PROJECT = Path(__file__).resolve().parents[2] / "godot-project"
BUNDLES = PROJECT / "assets" / "critical_sprites"
PNG_HEADER = b"\x89PNG\r\n\x1a\n"

TARGETS: dict[str, str] = {
    **{f"form1_walk_{d}_spec384": f"sprites/mollosar/form1_walk_{d}_spec384.png"
       for d in ("down", "up", "left", "right")},
    "form1_idle_down_spec384": "sprites/mollosar/form1_idle_down_spec384.png",
    "p1_bellhollow_bridge_1280x720": "assets/backgrounds/p1_bellhollow_bridge_1280x720.png",
    "mira": "assets/npc/mira.png",
    "wounded_soldier": "assets/npc/wounded_soldier.png",
    **{name: f"assets/creatures/{name}.png"
       for name in ("dragonthorn", "gloomcap", "spinehopper", "bellmaw", "wispwillow")},
}


def png_dimensions(data: bytes) -> tuple[int, int]:
    if len(data) < 33 or not data.startswith(PNG_HEADER) or data[12:16] != b"IHDR":
        raise ValueError("bad PNG signature/IHDR")
    width, height = struct.unpack(">II", data[16:24])
    if not 0 < width <= 20000 or not 0 < height <= 20000:
        raise ValueError("invalid PNG dimensions")
    return width, height


def restore() -> int:
    restored = 0
    errors = []
    for stem, relative in TARGETS.items():
        dest = PROJECT / relative
        if dest.is_file():
            existing = dest.read_bytes()
            if existing.startswith(PNG_HEADER):
                try:
                    png_dimensions(existing)
                    print(f"[ART-EXPORT] native approved PNG intact: {relative}")
                    continue
                except ValueError:
                    pass
        src = BUNDLES / f"{stem}.b64"
        if not src.is_file():
            src = BUNDLES / f"{stem}.png.b64"
        if not src.is_file():
            errors.append(f"missing exact approved source: {stem}")
            continue
        try:
            data = base64.b64decode(src.read_bytes().strip(), validate=True)
            width, height = png_dimensions(data)
        except (ValueError, OSError) as exc:
            errors.append(f"undecodable source {src.name}: {exc}")
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)
        restored += 1
        print(f"[ART-EXPORT] restored original {relative} ({width}x{height})")
    print(f"[ART-EXPORT] {restored} originals recovered; {len(errors)} missing")
    if errors:
        for error in errors:
            print("[ART-EXPORT] ERROR " + error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(restore())
