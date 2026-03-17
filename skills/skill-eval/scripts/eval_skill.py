#!/usr/bin/env python3
"""Evaluate and improve skill description triggering.

Uses only claude -p (subscription auth) — no ANTHROPIC_API_KEY needed.
Runs from an isolated temp directory with --setting-sources to prevent
the real skill from competing with the test command.
"""

import argparse
import json
import os
import random
import re
import select
import subprocess
import sys
import tempfile
import time
import uuid
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path


def parse_skill_md(skill_path: Path) -> tuple[str, str, str]:
    content = (skill_path / "SKILL.md").read_text()
    lines = content.split("\n")
    if lines[0].strip() != "---":
        raise ValueError("SKILL.md missing frontmatter")
    end_idx = None
    for i, line in enumerate(lines[1:], start=1):
        if line.strip() == "---":
            end_idx = i
            break
    if end_idx is None:
        raise ValueError("SKILL.md missing closing ---")

    name = ""
    description = ""
    frontmatter_lines = lines[1:end_idx]
    i = 0
    while i < len(frontmatter_lines):
        line = frontmatter_lines[i]
        if line.startswith("name:"):
            name = line[len("name:") :].strip().strip("\"'")
        elif line.startswith("description:"):
            value = line[len("description:") :].strip()
            if value in (">", "|", ">-", "|-"):
                parts: list[str] = []
                i += 1
                while i < len(frontmatter_lines) and (
                    frontmatter_lines[i].startswith("  ")
                    or frontmatter_lines[i].startswith("\t")
                ):
                    parts.append(frontmatter_lines[i].strip())
                    i += 1
                description = " ".join(parts)
                continue
            else:
                description = value.strip("\"'")
        i += 1
    return name, description, content


def run_single_query(
    query: str,
    skill_name: str,
    description: str,
    timeout: int,
    model: str | None,
) -> bool:
    """Run a single query in an isolated temp dir, return whether skill triggered."""
    unique_id = uuid.uuid4().hex[:8]
    clean_name = f"{skill_name}-skill-{unique_id}"
    tmpdir = tempfile.mkdtemp(prefix="skill-eval-")
    commands_dir = Path(tmpdir) / ".claude" / "commands"
    commands_dir.mkdir(parents=True)
    command_file = commands_dir / f"{clean_name}.md"

    try:
        indented_desc = "\n  ".join(description.split("\n"))
        command_file.write_text(
            f"---\n"
            f"description: |\n"
            f"  {indented_desc}\n"
            f"---\n\n"
            f"# {skill_name}\n\n"
            f"This skill handles: {description}\n"
        )

        cmd = [
            "claude",
            "-p",
            query,
            "--output-format",
            "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--setting-sources",
            "project,local",
        ]
        if model:
            cmd.extend(["--model", model])

        env = {k: v for k, v in os.environ.items() if k != "CLAUDECODE"}

        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            cwd=tmpdir,
            env=env,
        )

        pending_tool_name = None
        accumulated_json = ""
        start_time = time.time()
        buffer = ""

        try:
            while time.time() - start_time < timeout:
                if process.poll() is not None:
                    remaining = process.stdout.read()
                    if remaining:
                        buffer += remaining.decode("utf-8", errors="replace")
                    break

                ready, _, _ = select.select([process.stdout], [], [], 1.0)
                if not ready:
                    continue

                chunk = os.read(process.stdout.fileno(), 8192)
                if not chunk:
                    break
                buffer += chunk.decode("utf-8", errors="replace")

                while "\n" in buffer:
                    line, buffer = buffer.split("\n", 1)
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        event = json.loads(line)
                    except json.JSONDecodeError:
                        continue

                    if event.get("type") == "stream_event":
                        se = event.get("event", {})
                        se_type = se.get("type", "")

                        if se_type == "content_block_start":
                            cb = se.get("content_block", {})
                            if cb.get("type") == "tool_use":
                                tool_name = cb.get("name", "")
                                if tool_name in ("Skill", "Read"):
                                    pending_tool_name = tool_name
                                    accumulated_json = ""
                                else:
                                    # Other tools (ToolSearch, Bash, etc.)
                                    # — don't bail, keep scanning
                                    pending_tool_name = None

                        elif se_type == "content_block_delta" and pending_tool_name:
                            delta = se.get("delta", {})
                            if delta.get("type") == "input_json_delta":
                                accumulated_json += delta.get("partial_json", "")
                                if clean_name in accumulated_json:
                                    return True

                        elif se_type == "content_block_stop":
                            if pending_tool_name:
                                if clean_name in accumulated_json:
                                    return True
                            pending_tool_name = None

                        elif se_type == "message_stop":
                            pass  # let the loop continue to process remaining buffer

                    elif event.get("type") == "assistant":
                        message = event.get("message", {})
                        for content_item in message.get("content", []):
                            if content_item.get("type") != "tool_use":
                                continue
                            tool_name = content_item.get("name", "")
                            tool_input = content_item.get("input", {})
                            if tool_name == "Skill" and clean_name in tool_input.get(
                                "skill", ""
                            ):
                                return True
                            if tool_name == "Read" and clean_name in tool_input.get(
                                "file_path", ""
                            ):
                                return True

                    elif event.get("type") == "result":
                        return False
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()

        return False
    finally:
        import shutil

        shutil.rmtree(tmpdir, ignore_errors=True)


def run_eval(
    eval_set: list[dict],
    skill_name: str,
    description: str,
    num_workers: int,
    timeout: int,
    runs_per_query: int,
    trigger_threshold: float,
    model: str | None,
) -> dict:
    results = []
    with ProcessPoolExecutor(max_workers=num_workers) as executor:
        future_to_info = {}
        for item in eval_set:
            for run_idx in range(runs_per_query):
                future = executor.submit(
                    run_single_query,
                    item["query"],
                    skill_name,
                    description,
                    timeout,
                    model,
                )
                future_to_info[future] = (item, run_idx)

        query_triggers: dict[str, list[bool]] = {}
        query_items: dict[str, dict] = {}
        for future in as_completed(future_to_info):
            item, _ = future_to_info[future]
            query = item["query"]
            query_items[query] = item
            if query not in query_triggers:
                query_triggers[query] = []
            try:
                query_triggers[query].append(future.result())
            except Exception as e:
                print(f"Warning: query failed: {e}", file=sys.stderr)
                query_triggers[query].append(False)

    for query, triggers in query_triggers.items():
        item = query_items[query]
        trigger_rate = sum(triggers) / len(triggers)
        should_trigger = item["should_trigger"]
        did_pass = (
            trigger_rate >= trigger_threshold
            if should_trigger
            else trigger_rate < trigger_threshold
        )
        results.append(
            {
                "query": query,
                "should_trigger": should_trigger,
                "trigger_rate": trigger_rate,
                "triggers": sum(triggers),
                "runs": len(triggers),
                "pass": did_pass,
            }
        )

    passed = sum(1 for r in results if r["pass"])
    return {
        "skill_name": skill_name,
        "description": description,
        "results": results,
        "summary": {
            "total": len(results),
            "passed": passed,
            "failed": len(results) - passed,
        },
    }


def improve_description(
    skill_name: str,
    skill_content: str,
    current_description: str,
    eval_results: dict,
    history: list[dict],
    model: str,
) -> str:
    """Use claude -p to propose an improved description."""
    failed_triggers = [
        r for r in eval_results["results"] if r["should_trigger"] and not r["pass"]
    ]
    false_triggers = [
        r for r in eval_results["results"] if not r["should_trigger"] and not r["pass"]
    ]
    score = f"{eval_results['summary']['passed']}/{eval_results['summary']['total']}"

    prompt_parts = [
        f'You are optimizing a skill description for "{skill_name}".',
        f"Current description:\n{current_description}\n",
        f"Current score: {score}",
    ]
    if failed_triggers:
        prompt_parts.append("FAILED TO TRIGGER (should have but didn't):")
        for r in failed_triggers:
            prompt_parts.append(
                f'  - "{r["query"][:100]}" (triggered {r["triggers"]}/{r["runs"]})'
            )
    if false_triggers:
        prompt_parts.append("FALSE TRIGGERS (triggered but shouldn't have):")
        for r in false_triggers:
            prompt_parts.append(
                f'  - "{r["query"][:100]}" (triggered {r["triggers"]}/{r["runs"]})'
            )
    if history:
        prompt_parts.append("PREVIOUS ATTEMPTS (try something structurally different):")
        for h in history:
            s = f"{h['passed']}/{h['total']}"
            prompt_parts.append(f'  [{s}] "{h["description"][:120]}"')

    prompt_parts.append(f"Skill content for context:\n{skill_content}\n")
    prompt_parts.append(
        "Write an improved description (100-200 words max) that triggers for "
        "relevant queries and doesn't trigger for irrelevant ones. Generalize "
        "from failures — don't overfit to specific queries. Focus on user intent. "
        "Respond with ONLY the new description inside <new_description> tags."
    )

    prompt = "\n\n".join(prompt_parts)
    cmd = ["claude", "-p", prompt, "--output-format", "text", "--model", model]
    env = {k: v for k, v in os.environ.items() if k != "CLAUDECODE"}

    result = subprocess.run(cmd, capture_output=True, text=True, timeout=120, env=env)
    text = result.stdout.strip()

    match = re.search(r"<new_description>(.*?)</new_description>", text, re.DOTALL)
    return match.group(1).strip().strip('"') if match else text.strip().strip('"')


def print_eval_stats(label: str, results: list[dict], elapsed: float) -> None:
    pos = [r for r in results if r["should_trigger"]]
    neg = [r for r in results if not r["should_trigger"]]
    tp = sum(r["triggers"] for r in pos)
    pos_runs = sum(r["runs"] for r in pos)
    fn = pos_runs - tp
    fp = sum(r["triggers"] for r in neg)
    neg_runs = sum(r["runs"] for r in neg)
    tn = neg_runs - fp
    total = tp + tn + fp + fn
    precision = tp / (tp + fp) if (tp + fp) > 0 else 1.0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 1.0
    accuracy = (tp + tn) / total if total > 0 else 0.0
    print(
        f"{label}: {tp + tn}/{total} correct, "
        f"precision={precision:.0%} recall={recall:.0%} accuracy={accuracy:.0%} "
        f"({elapsed:.1f}s)",
        file=sys.stderr,
    )
    for r in results:
        status = "PASS" if r["pass"] else "FAIL"
        print(
            f"  [{status}] rate={r['triggers']}/{r['runs']} "
            f"expected={r['should_trigger']}: {r['query'][:70]}",
            file=sys.stderr,
        )


def main():
    parser = argparse.ArgumentParser(
        description="Evaluate and improve skill description triggering"
    )
    parser.add_argument("--eval-set", required=True, help="Path to eval set JSON")
    parser.add_argument("--skill-path", required=True, help="Path to skill directory")
    parser.add_argument("--model", default=None, help="Model for claude -p")
    parser.add_argument(
        "--num-workers", type=int, default=5, help="Parallel workers (default: 5)"
    )
    parser.add_argument(
        "--timeout", type=int, default=60, help="Timeout per query in seconds"
    )
    parser.add_argument("--runs-per-query", type=int, default=3, help="Runs per query")
    parser.add_argument(
        "--trigger-threshold", type=float, default=0.5, help="Trigger rate threshold"
    )
    parser.add_argument(
        "--improve", action="store_true", help="Run improvement loop after eval"
    )
    parser.add_argument(
        "--max-iterations", type=int, default=3, help="Max improvement iterations"
    )
    parser.add_argument(
        "--holdout", type=float, default=0.4, help="Fraction held out for test"
    )
    args = parser.parse_args()

    eval_set = json.loads(Path(args.eval_set).read_text())
    skill_path = Path(args.skill_path)
    if not (skill_path / "SKILL.md").exists():
        print(f"Error: No SKILL.md at {skill_path}", file=sys.stderr)
        sys.exit(1)

    name, description, content = parse_skill_md(skill_path)
    current_description = description

    # Split train/test
    if args.improve and args.holdout > 0:
        random.seed(42)
        trigger = [e for e in eval_set if e["should_trigger"]]
        no_trigger = [e for e in eval_set if not e["should_trigger"]]
        random.shuffle(trigger)
        random.shuffle(no_trigger)
        nt = max(1, int(len(trigger) * args.holdout))
        nn = max(1, int(len(no_trigger) * args.holdout))
        test_set = trigger[:nt] + no_trigger[:nn]
        train_set = trigger[nt:] + no_trigger[nn:]
        print(
            f"Split: {len(train_set)} train, {len(test_set)} test",
            file=sys.stderr,
        )
    else:
        train_set = eval_set
        test_set = []

    history: list[dict] = []
    max_iters = args.max_iterations if args.improve else 1

    for iteration in range(1, max_iters + 1):
        print(f"\n{'=' * 60}", file=sys.stderr)
        print(f"Iteration {iteration}/{max_iters}", file=sys.stderr)
        print(f"Description: {current_description[:120]}...", file=sys.stderr)
        print(f"{'=' * 60}", file=sys.stderr)

        t0 = time.time()
        all_queries = train_set + test_set
        all_results = run_eval(
            eval_set=all_queries,
            skill_name=name,
            description=current_description,
            num_workers=args.num_workers,
            timeout=args.timeout,
            runs_per_query=args.runs_per_query,
            trigger_threshold=args.trigger_threshold,
            model=args.model,
        )
        elapsed = time.time() - t0

        train_queries = {q["query"] for q in train_set}
        train_results = [
            r for r in all_results["results"] if r["query"] in train_queries
        ]
        test_results = [
            r for r in all_results["results"] if r["query"] not in train_queries
        ]

        print_eval_stats("Train", train_results, elapsed)
        if test_results:
            print_eval_stats("Test ", test_results, 0)

        train_passed = sum(1 for r in train_results if r["pass"])
        train_total = len(train_results)

        history.append(
            {
                "iteration": iteration,
                "description": current_description,
                "passed": train_passed,
                "total": train_total,
                "results": train_results,
            }
        )

        if train_passed == train_total:
            print(f"\nAll train queries passed!", file=sys.stderr)
            break

        if not args.improve or iteration == max_iters:
            break

        print(f"\nImproving description via claude -p...", file=sys.stderr)
        t0 = time.time()
        new_description = improve_description(
            skill_name=name,
            skill_content=content,
            current_description=current_description,
            eval_results={
                "results": train_results,
                "summary": {
                    "total": train_total,
                    "passed": train_passed,
                    "failed": train_total - train_passed,
                },
            },
            history=history,
            model=args.model,
        )
        print(
            f"Proposed ({time.time() - t0:.1f}s): {new_description[:120]}...",
            file=sys.stderr,
        )
        current_description = new_description

    # Output best result
    if test_set:
        best = max(
            history,
            key=lambda h: sum(
                1
                for r in all_results["results"]
                if r["query"] not in {q["query"] for q in train_set} and r["pass"]
            ),
        )
    else:
        best = max(history, key=lambda h: h["passed"])

    output = {
        "original_description": description,
        "best_description": best["description"],
        "best_score": f"{best['passed']}/{best['total']}",
        "iterations_run": len(history),
        "history": history,
    }
    print(json.dumps(output, indent=2))


if __name__ == "__main__":
    main()
