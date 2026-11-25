import json
import tempfile
import unittest
from pathlib import Path
from tournament_context import load_context, render_context


class TournamentContextTests(unittest.TestCase):
    def test_stale_evidence_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'context.json'
            path.write_text(json.dumps({'reportDate': '2026-11-24'}))
            with self.assertRaises(ValueError):
                load_context(path, '2026-11-25')

    def test_missing_mapping_is_not_no_tournament(self):
        self.assertIn('待接入', render_context(None))
        self.assertIn('不能直接认定', render_context(None))

    def test_zero_baseline_and_escaped_labels(self):
        result = render_context({'category': '<LOL>', 'reportDate': '2026-11-24', 'comparisonDate': '2026-11-17',
                                 'metrics': [{'label': '拉新', 'current': 10, 'previous': 0, 'scope': '四端'}],
                                 'notes': [], 'sources': []})
        self.assertIn('基期为零', result)
        self.assertIn('&lt;LOL&gt;', result)


if __name__ == '__main__':
    unittest.main()
