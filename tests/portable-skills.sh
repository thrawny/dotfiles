#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd -P)
manifest="$repo_root/portable/macos/skills.sources.tsv"
workspace="$repo_root/portable/macos/generated/agent-skills"
skills_root="$workspace/.agents/skills"
lockfile="$workspace/skills-lock.json"
temp_root=$(mktemp -d)
trap 'rm -rf "$temp_root"' EXIT

expected_names="$temp_root/expected"
generated_names="$temp_root/generated"
lock_names="$temp_root/lock"
: >"$expected_names"

while IFS=$'\t' read -r source skill_list license_path; do
  [[ -z "$source" || "$source" == \#* ]] && continue
  [[ "$source" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]
  [[ -n "$skill_list" && -n "$license_path" ]]
  license_name=${source//\//--}.LICENSE
  [[ -s "$workspace/licenses/$license_name" ]]
  read -r -a selected_skills <<<"$skill_list"
  for skill_name in "${selected_skills[@]}"; do
    [[ "$skill_name" =~ ^[A-Za-z0-9_.-]+$ ]]
    printf '%s\n' "$skill_name" >>"$expected_names"
  done
done <"$manifest"

if [[ $(sort "$expected_names" | uniq -d | wc -l | tr -d ' ') -ne 0 ]]; then
  echo "portable skills test: duplicate names in $manifest" >&2
  exit 1
fi
sort -o "$expected_names" "$expected_names"

: >"$generated_names"
for skill_dir in "$skills_root"/*; do
  [[ -d "$skill_dir" ]] || continue
  [[ -f "$skill_dir/SKILL.md" ]]
  basename "$skill_dir" >>"$generated_names"
done
sort -o "$generated_names" "$generated_names"
diff -u "$expected_names" "$generated_names"

jq -er '(.version | type == "number") and (.skills | type == "object")' "$lockfile" >/dev/null
jq -r '.skills | keys[]' "$lockfile" | sort >"$lock_names"
diff -u "$expected_names" "$lock_names"

while IFS= read -r skill_name; do
  if [[ -d "$repo_root/skills/$skill_name" || -d "$repo_root/config/codex/commands/$skill_name" ]]; then
    echo "portable skills test: generated skill collides with repo skill: $skill_name" >&2
    exit 1
  fi
done <"$expected_names"

printf 'portable skills test: ok\n'
