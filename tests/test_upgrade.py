import contextlib
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import setup
from dashboard.app import load_rows, render

class UpgradeTest(unittest.TestCase):
    def test_wizard_writes_valid_values_and_keeps_paths(self):
        with tempfile.TemporaryDirectory() as d:
            config = Path(d)/'monitor.conf'
            config.write_text((Path(__file__).resolve().parents[1]/'config/monitor.conf').read_text())
            before=config.read_text()
            with patch.object(sys,'argv',['setup.py','--config',str(config)]), patch('builtins.input', side_effect=['']*12), contextlib.redirect_stdout(io.StringIO()):
                setup.main()
            after=config.read_text()
            self.assertIn('CPU_WARN=80',after)
            self.assertIn('LOG_DIR="./logs"',after)
            self.assertEqual(before,after)
    def test_wizard_does_not_save_if_declined(self):
        with tempfile.TemporaryDirectory() as d:
            config=Path(d)/'monitor.conf'; config.write_text((Path(__file__).resolve().parents[1]/'config/monitor.conf').read_text())
            before=config.read_text()
            with patch.object(sys,'argv',['setup.py','--config',str(config)]), patch('builtins.input', side_effect=['']*11+['no']), contextlib.redirect_stdout(io.StringIO()):
                setup.main()
            self.assertEqual(before,config.read_text())
    def test_dashboard_escapes_csv_content_and_reads_recent(self):
        with tempfile.TemporaryDirectory() as d:
            csv=Path(d)/'metrics.csv'
            csv.write_text('2026-09-27 13:00:00,cpu,12.5,OK,<script>alert(1)</script>\n2026-09-27 13:01:00,cpu,20,WARN,busy\n')
            rows=load_rows(csv); html=render(rows)
            self.assertEqual(len(rows),2)
            self.assertIn('CPU',html)
            self.assertNotIn('&lt;script&gt;',html)
            self.assertNotIn('<script>',html)
            self.assertIn('busy',html)
            self.assertIn('&lt;script&gt;',render(rows[:1]))
    def test_empty_dashboard(self):
        self.assertIn('No checks recorded',render([]))
        self.assertEqual(load_rows(Path('/nonexistent/metrics.csv')),[])

if __name__=='__main__': unittest.main()
