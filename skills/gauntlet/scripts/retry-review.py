#!/usr/bin/env python3
"""Run one reviewer serially; persist evidence before any retry or result use."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time


def fingerprint(scope=None):
    scope = os.environ.get('GAUNTLET_REVIEW_SCOPE', '') if scope is None else scope
    digest = hashlib.sha256()
    def contribute(value):
        digest.update(len(value).to_bytes(8, 'big'))
        digest.update(value)
    contribute(scope.encode())
    if scope.startswith(('--base ', '--commit ')):
        ref = scope.split(' ', 1)[1]
        resolved = subprocess.run(['git', 'rev-parse', '--verify', ref], capture_output=True, check=True)
        contribute(resolved.stdout)
    for args in (["rev-parse", "HEAD"], ["diff", "HEAD", "--binary"],
                 ["ls-files", "--others", "--exclude-standard", "-z"]):
        result = subprocess.run(["git", *args], capture_output=True)
        contribute(result.stdout)
        if args[0] == "ls-files":
            for name in result.stdout.split(b"\0"):
                if name:
                    p = Path(os.fsdecode(name))
                    contribute(name)
                    contribute(b'symlink' if p.is_symlink() else b'file')
                    contribute(os.fsencode(os.readlink(p)) if p.is_symlink() else p.read_bytes())
    return digest.hexdigest()


def classify(code, text):
    if code == 0:
        return "ok"
    text = text.lower()
    if code in (130, 143) or code < 0:
        return "human-stop"
    if re.search(r'401|403|unauthorized|authenticat|not logged in|invalid.api.key|no credentials', text):
        return "auth"
    if re.search(r'quota|usage limit|out of credit|insufficient.credit|billing', text):
        return "quota"
    if re.search(r'429|rate.?limit|too many requests|capacity|overloaded|temporar|503|502|504|connection reset|connection closed|connection refused|timed? out|timeout|transport error', text):
        return "transient"
    return "terminal"


def reset_at(text):
    match = re.search(r'"?resetAt"?\s*[:=]\s*"?([^"\s,}]+)', text)
    if match:
        try:
            value = match[1]
            if value.replace('.', '', 1).isdigit():
                parsed = datetime.datetime.fromtimestamp(float(value), datetime.timezone.utc)
            else:
                parsed = datetime.datetime.fromisoformat(value.replace('Z', '+00:00'))
                if parsed.tzinfo is None:
                    return None
            return parsed.astimezone(datetime.timezone.utc).isoformat().replace('+00:00', 'Z')
        except (ValueError, OverflowError, OSError):
            pass
    return None


def delay(attempt, text, now):
    reset = reset_at(text)
    earliest = datetime.datetime.fromisoformat(reset.replace('Z', '+00:00')).timestamp() if reset else now
    match = re.search(r'retry-after\s*[:=]\s*(\d+)', text, re.I)
    return max(min(30 * 2 ** (attempt - 1), 120), earliest - now, int(match[1]) if match else 0)


def run(directory, engine, output, command, *, invoke=subprocess.run, sleep=time.sleep, clock=time.time):
    directory = Path(directory)
    events = directory / f"{engine}.attempts.jsonl"
    original = os.environ.get("GAUNTLET_SCOPE_FINGERPRINT") or fingerprint()
    head = subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
    started = clock()
    for attempt in range(1, 4):
        raw = directory / f"{engine}.attempt-{attempt}.log"
        answer = directory / f"{engine}.attempt-{attempt}.out"
        argv = [str(answer) if arg == output else arg for arg in command]
        # Record launch intent durably. An interrupted/unknown attempt is never replayed.
        def record(**data):
            with events.open('a') as stream:
                stream.write(json.dumps(dict(schemaVersion=1, engine=engine, attempt=attempt, maxAttempts=3, fingerprint=original, head_sha=head, **data)) + '\n')
                stream.flush()
                os.fsync(stream.fileno())
        if attempt > 1 and clock() - started > 300:
            record(state='transient', retry_owner='gauntlet', retryable=True, exhausted=True)
            return 1
        if fingerprint() != original:
            record(state='scope-changed', retry_owner='gauntlet')
            return 1
        record(state="running", argv=argv, at=clock())
        try:
            with raw.open('wb') as stream:
                result = invoke(argv, stdout=stream, stderr=subprocess.STDOUT)
            text = raw.read_text(errors='replace')
            if answer.exists():
                text += '\n' + answer.read_text(errors='replace')
            kind = classify(result.returncode, text)
        except OSError as error:
            raw.write_text(str(error))
            kind = 'terminal'
            text = str(error)
        if fingerprint() != original:
            kind = 'scope-changed'
        if kind == 'ok' and (not answer.exists() or not answer.stat().st_size if engine == 'codex' else not raw.stat().st_size):
            kind = 'empty-result'
        wait = delay(attempt, text, clock()) if kind == 'transient' else 0
        retry = kind == 'transient' and attempt < 3 and clock() + wait - started <= 300
        if kind == 'ok':
            try:
                Path(output).write_bytes(answer.read_bytes() if engine == 'codex' else raw.read_bytes())
            except OSError:
                kind = 'output-error'
        record(state='retry-wait' if retry else kind, retryable=kind == 'transient',
               retry_owner='gauntlet', exhausted=kind == 'transient' and not retry,
               next_attempt_at=clock() + wait if retry else None,
               resetAt=reset_at(text) if kind == 'transient' else None, raw=str(raw))
        if kind == 'ok':
            return 0
        if not retry:
            print(f'{engine}: blocked ({kind}); evidence: {events}', file=sys.stderr)
            return 1
        print(f'{engine}: transient failure; retry {attempt + 1}/3 in {wait:.0f}s; evidence: {events}', file=sys.stderr)
        sleep(wait)
        if fingerprint() != original:
            record(state='scope-changed', retry_owner='gauntlet')
            return 1
    return 1


if __name__ == '__main__':
    sys.exit(run(*sys.argv[1:4], sys.argv[4:]))
