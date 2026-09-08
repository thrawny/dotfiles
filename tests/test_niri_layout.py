"""Exercise monitor detection without changing the running desktop."""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PHILIPS = "Philips Consumer Electronics Company"


class NiriLayoutTests(unittest.TestCase):
    def run_work(self, outputs, query_exit=0):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            log = base / "calls"
            log.touch()
            for name in ("niri", "niri-move-workspaces", "niri-set-column-width"):
                stub = base / name
                stub.write_text(
                    "#!/usr/bin/env bash\n"
                    'if [[ "${0##*/}" == niri && "$*" == "msg -j outputs" ]]; then\n'
                    '  printf "%s\\n" "$OUTPUTS"\n'
                    '  exit "$QUERY_EXIT"\n'
                    "fi\n"
                    'printf "%s %s\\n" "${0##*/}" "$*" >> "$CALLS"\n'
                )
                stub.chmod(0o755)
            result = subprocess.run(
                ["bash", str(ROOT / "bin/niri-layout"), "work"],
                env={
                    **os.environ,
                    "PATH": f"{base}{os.pathsep}{os.environ['PATH']}",
                    "OUTPUTS": json.dumps(outputs),
                    "QUERY_EXIT": str(query_exit),
                    "CALLS": str(log),
                    "TRACE": "",
                },
                capture_output=True,
                text=True,
                check=False,
            )
            return result, log.read_text().splitlines()

    def test_work_follows_philips_across_connectors(self):
        for connector in ("DP-1", "DP-2", "DP-8", "HDMI-A-1"):
            with self.subTest(connector=connector):
                result, calls = self.run_work(
                    {
                        "eDP-1": {"name": "eDP-1", "make": "Lenovo Group Limited"},
                        "DP-3": {"name": "DP-3", "make": "LG Electronics"},
                        connector: {
                            "name": connector,
                            "make": PHILIPS,
                            "model": "PHL34E1C5600",
                        },
                    }
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(
                    calls,
                    [
                        "niri msg output eDP-1 on",
                        f"niri-move-workspaces {connector} --except main",
                        "niri msg action move-workspace-to-monitor --reference main eDP-1",
                        "niri-set-column-width 0.33333",
                    ],
                )

    def test_missing_or_ambiguous_monitor_does_not_change_layout(self):
        for outputs in (
            {},
            {"DP-1": {"name": "DP-1", "make": "LG Electronics"}},
            {name: {"name": name, "make": PHILIPS} for name in ("DP-1", "DP-2")},
        ):
            with self.subTest(outputs=outputs):
                result, calls = self.run_work(outputs)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("exactly one connected Philips monitor", result.stderr)
                self.assertEqual(calls, [])

    def test_query_failure_does_not_change_layout(self):
        result, calls = self.run_work(
            {"DP-2": {"name": "DP-2", "make": PHILIPS}}, query_exit=1
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])
