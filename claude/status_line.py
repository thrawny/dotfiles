#!/usr/bin/env python3
import json
import os
import sys

# Read JSON from stdin
data = json.load(sys.stdin)

# Extract values
model = data["model"]["display_name"]
current_dir = os.path.basename(data["workspace"]["current_dir"])

# Check for git branch
git_branch = ""
if os.path.exists(".git"):
    try:
        with open(".git/HEAD", "r") as f:
            ref = f.read().strip()
            if ref.startswith("ref: refs/heads/"):
                git_branch = f" | 🌿 {ref.replace('ref: refs/heads/', '')}"
    except:  # noqa: E722
        pass

print(f"[{model}] 📁 {current_dir}{git_branch}")
