#!/usr/bin/env python3
"""Offline regression tests for the read-only Form 1 frame review tool."""
import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from PIL import Image

from form1_frame_review import inspect_frame, islands, review


class FrameReviewTests(unittest.TestCase):
    def test_islands_and_clipping(self):
        frame = Image.new("RGBA", (16, 16))
        for y in range(4, 10):
            for x in range(4, 10):
                frame.putpixel((x, y), (50, 60, 70, 255))
        for x in range(8):
            frame.putpixel((x, 0), (70, 80, 90, 255))
        report = inspect_frame(frame)
        self.assertTrue(report["edge_touch"])
        self.assertTrue(report["alpha_binary"])
        self.assertEqual(report["islands_ge8"], 2)
        self.assertEqual(report["bbox"], "0,0,10,10")

    def test_semitransparency_flag(self):
        frame = Image.new("RGBA", (16, 16))
        frame.putpixel((3, 3), (255, 255, 255, 128))
        self.assertFalse(inspect_frame(frame)["alpha_binary"])

    def test_report_preserves_source(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            art = root / "godot-project/sprites/mollosar/approved"
            art.mkdir(parents=True)
            path = art / "form1_slash_side-r.png"
            strip = Image.new("RGBA", (32, 16))
            for y in range(4, 12):
                for x in range(4, 12):
                    strip.putpixel((x, y), (50, 100, 150, 255))
            strip.save(path)
            manifest = art / "form1_attack_manifest.json"
            manifest.write_text(json.dumps({"status": "APPROVED", "strips": {
                "slash_side-r": {"frames": 2, "cell": [16, 16],
                                 "texture": "res://sprites/mollosar/approved/form1_slash_side-r.png"}
            }}))
            before = hashlib.sha256(path.read_bytes()).hexdigest()
            rows = review(manifest, "slash_side-r", root / "report")
            self.assertEqual(len(rows), 2)
            self.assertEqual(before, hashlib.sha256(path.read_bytes()).hexdigest())
            self.assertTrue((root / "report/slash_side-r/contact.png").exists())
            self.assertTrue((root / "report/frame_diagnostics.csv").exists())
            self.assertEqual(rows[0]["frame_zero_based"], 0)
            self.assertEqual(rows[1]["frame_zero_based"], 1)

    def test_invalid_clip_does_not_modify_art(self):
        with tempfile.TemporaryDirectory() as d:
            manifest = Path(d) / "manifest.json"
            manifest.write_text(json.dumps({"status": "APPROVED", "strips": {}}))
            with self.assertRaises(ValueError):
                review(manifest, "not_a_clip", Path(d) / "output")


if __name__ == "__main__":
    unittest.main()
