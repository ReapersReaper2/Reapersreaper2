"""Regression checks for false greens, bounded processes and path quoting."""
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
import os

spec = importlib.util.spec_from_file_location('runner', Path(__file__).with_name('run_godot_tests.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class RunnerTests(unittest.TestCase):
    def invoke(self, code, timeout=5):
        with tempfile.TemporaryDirectory(prefix='rebirth path with spaces ') as tmp:
            return runner.run(Path(sys.executable), ['-c', code], Path(tmp), 'fixture', timeout, os.environ.copy())[0]

    def test_clean_process(self):
        self.assertEqual(self.invoke('print("PASS 4 checks")')['result'], 'PASS')

    def test_script_argument_with_spaces(self):
        with tempfile.TemporaryDirectory(prefix='rebirth path with spaces ') as tmp:
            script = Path(tmp) / 'test program.py'
            script.write_text('import sys; assert sys.argv[1] == "argument with spaces"')
            result, _ = runner.run(Path(sys.executable), [str(script), 'argument with spaces'], Path(tmp), 'fixture', 5, os.environ.copy())
            self.assertEqual(result['result'], 'PASS')

    def test_zero_exit_script_error(self):
        self.assertEqual(self.invoke('print("SCRIPT ERROR: failed assertion")')['result'], 'FAIL')

    def test_stderr_error(self):
        self.assertEqual(self.invoke('import sys; print("ERROR: missing asset", file=sys.stderr)')['result'], 'FAIL')

    def test_nonzero(self):
        self.assertEqual(self.invoke('raise SystemExit(3)')['exit_code'], 3)

    def test_timeout(self):
        self.assertTrue(self.invoke('import time; time.sleep(30)', timeout=1)['timed_out'])

    def test_assertion_marker(self):
        self.assertEqual(self.invoke('print("FAILED regression")')['result'], 'FAIL')


if __name__ == '__main__':
    unittest.main()
