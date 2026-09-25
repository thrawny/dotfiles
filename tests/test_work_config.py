"""Value lookup and the jira-cli fallback, against temporary config files."""

import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "bin/work-config"


def run(tmp_path: Path, *args: str, config: str | None = None, jira: str | None = None):
    config_file = tmp_path / "config.toml"
    if config is not None:
        config_file.write_text(config)
    jira_file = tmp_path / "jira.yml"
    if jira is not None:
        jira_file.write_text(jira)
    env = {
        "PATH": os.environ["PATH"],
        "WORK_CONFIG": str(config_file),
        "JIRA_CONFIG_FILE": str(jira_file),
    }
    return subprocess.run(
        [str(SCRIPT), *args], capture_output=True, text=True, env=env, check=False
    )


def test_prints_strings_and_lists_one_per_line(tmp_path: Path) -> None:
    config = '[github]\nreview_team = "acme/team"\nextra_review_repos = ["a", "b"]\n'
    assert run(tmp_path, "github.review_team", config=config).stdout == "acme/team\n"
    assert run(tmp_path, "github.extra_review_repos", config=config).stdout == "a\nb\n"


def test_missing_file_key_or_table_exits_1_quietly(tmp_path: Path) -> None:
    for result in (
        run(tmp_path, "github.review_team"),
        run(tmp_path, "github.nope", config="[github]\n"),
        run(tmp_path, "github", config='[github]\nreview_team = "x"\n'),
    ):
        assert (result.returncode, result.stdout) == (1, "")


def test_jira_url_falls_back_to_jira_cli_server(tmp_path: Path) -> None:
    jira = 'installation: Cloud\nserver: "https://jira.example.com/"\n'
    result = run(tmp_path, "jira.browse_url", config="", jira=jira)
    assert result.stdout == "https://jira.example.com/browse\n"


def test_configured_jira_url_wins_over_jira_cli(tmp_path: Path) -> None:
    config = '[jira]\nbrowse_url = "https://other.example.com/browse"\n'
    jira = "server: https://jira.example.com\n"
    result = run(tmp_path, "jira.browse_url", config=config, jira=jira)
    assert result.stdout == "https://other.example.com/browse\n"
