"""Expected baseline failures must not hide additional engine failures."""
import unittest
from run_form1_evidence import expected_regression, EXPECTED_BEFORE


class BaselineDiagnosticTests(unittest.TestCase):
    def setUp(self):
        self.result = dict(exit_code=1, timed_out=False, engine_errors=3)
        self.log = '\n'.join('ERROR: [FORM1 ANIMATION RUNTIME] ' + e for e in EXPECTED_BEFORE)

    def test_exact_known_regressions_are_classified(self):
        self.assertTrue(expected_regression(self.result, self.log, EXPECTED_BEFORE))

    def test_extra_engine_failure_cannot_hide_behind_baseline(self):
        self.result['engine_errors'] += 1
        self.assertFalse(expected_regression(self.result, self.log + '\nSCRIPT ERROR: unrelated', EXPECTED_BEFORE))

    def test_timeout_cannot_pass_as_expected_failure(self):
        self.result['timed_out'] = True
        self.assertFalse(expected_regression(self.result, self.log, EXPECTED_BEFORE))

    def test_different_regression_is_not_accepted(self):
        self.assertFalse(expected_regression(self.result, self.log.replace('stopping during frame zero resets gait clock', 'missing art'), EXPECTED_BEFORE))


if __name__ == '__main__':
    unittest.main()
