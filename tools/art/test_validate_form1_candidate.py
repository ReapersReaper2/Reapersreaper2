#!/usr/bin/env python3
"""Regression tests for candidate-only Form 1 sprite intake."""
import tempfile
import unittest
from pathlib import Path
from PIL import Image
from validate_form1_candidate import validate, CELL


class CandidateIntakeTests(unittest.TestCase):
    def test_valid_rgba_candidate_passes_technical_gate(self):
        with tempfile.TemporaryDirectory() as folder:
            image = Image.new("RGBA", (CELL * 6, CELL), (0, 0, 0, 0))
            for i in range(6):
                for y in range(30, 377):
                    for x in range(100, 260):
                        image.putpixel((i * CELL + x, y), (60, 100, 50, 255))
            path = Path(folder) / "candidate.png"
            image.save(path)
            errors, warnings = validate(path, "slash")
            self.assertEqual(errors, [])
            self.assertEqual(warnings, [])

    def test_opaque_rgb_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "rgb.png"
            Image.new("RGB", (CELL * 6, CELL), "white").save(path)
            errors, _ = validate(path, "slash")
            self.assertTrue(any("RGBA" in e for e in errors))

    def test_wrong_size_and_semitransparency_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "wrong.png"
            image = Image.new("RGBA", (CELL * 6 - 1, CELL), (0, 0, 0, 0))
            image.putpixel((100, 100), (255, 255, 255, 128))
            image.save(path)
            errors, _ = validate(path, "slash")
            self.assertTrue(any("size" in e.lower() for e in errors))
            self.assertTrue(any("nonbinary" in e for e in errors))

    def test_fully_opaque_rgba_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "opaque.png"
            Image.new("RGBA", (CELL * 6, CELL), (255, 255, 255, 255)).save(path)
            errors, _ = validate(path, "slash")
            self.assertTrue(any("transparent" in e for e in errors))

    def test_missing_and_unknown_action_fail(self):
        errors, _ = validate(Path("/nonexistent/candidate.png"), "slash")
        self.assertTrue(errors)
        errors, _ = validate(Path("/nonexistent/candidate.png"), "unknown")
        self.assertTrue(errors)


if __name__ == "__main__":
    unittest.main()
