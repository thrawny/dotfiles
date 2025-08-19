#!/usr/bin/env python3
import json
import os
import subprocess
import sys

# Read JSON from stdin
data = json.load(sys.stdin)

# Extract values
model = data["model"]["display_name"]
current_dir = os.path.basename(data["workspace"]["current_dir"])

# Check for git branch (with worktree support)
git_branch = ""
try:
    # Use git to get the branch name - works with regular repos and worktrees
    result = subprocess.run(
        ["git", "symbolic-ref", "--short", "HEAD"],
        capture_output=True,
        text=True,
        timeout=1,
    )
    if result.returncode == 0:
        branch = result.stdout.strip()
        git_branch = f" | 🌿 {branch}"
except (subprocess.TimeoutExpired, subprocess.CalledProcessError, FileNotFoundError):
    # Fallback to checking .git/HEAD if git command fails
    if os.path.exists(".git"):
        try:
            # Check if .git is a file (worktree) or directory (regular repo)
            if os.path.isfile(".git"):
                # It's a worktree - read the gitdir path
                with open(".git", "r") as f:
                    gitdir_line = f.read().strip()
                    if gitdir_line.startswith("gitdir: "):
                        gitdir = gitdir_line[8:]
                        head_file = os.path.join(gitdir, "HEAD")
                        if os.path.exists(head_file):
                            with open(head_file, "r") as f:
                                ref = f.read().strip()
                                if ref.startswith("ref: refs/heads/"):
                                    git_branch = (
                                        f" | 🌿 {ref.replace('ref: refs/heads/', '')}"
                                    )
            else:
                # Regular repo
                with open(".git/HEAD", "r") as f:
                    ref = f.read().strip()
                    if ref.startswith("ref: refs/heads/"):
                        git_branch = f" | 🌿 {ref.replace('ref: refs/heads/', '')}"
        except:  # noqa: E722
            pass

print(f"[{model}] 📁 {current_dir}{git_branch}")
