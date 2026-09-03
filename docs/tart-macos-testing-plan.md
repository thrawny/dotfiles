# Tart macOS VM testing plan

Planning snapshot: 2026-09-03. Status: proposed.

## Decision

Use [Tart](https://github.com/openai/tart) on an Apple Silicon Mac to run the
portable macOS setup in disposable macOS VMs. Tart uses Apple's
`Virtualization.framework`, has a scriptable CLI, and can clone cached VM images
with copy-on-write storage.

Keep Tart as a host-side test dependency rather than adding it to `Brewfile`.
The package installer runs inside the guest, where installing a hypervisor would
be unnecessary and nested virtualization is not part of the test.

## Intended outcome

One root command should test the current checkout on clean Apple Silicon macOS:

```bash
just test-macos-vm
```

The command will:

1. make a disposable clone of a known macOS base image;
2. boot it without a graphical window;
3. copy a secret-free snapshot of the current checkout to `~/dotfiles` in the
   guest;
4. run setup, package installation, consumer smoke tests, macOS defaults, and
   `bin/check-macos`;
5. return the guest test's exit code; and
6. stop and delete the clone even when a test fails.

A failure should print the retained host log path. An explicit `--keep` option
should preserve the failed VM for inspection.

## Scope

The VM test should cover behavior that the current tests cannot:

- the `Darwin` and `arm64` guards;
- Homebrew formulas and macOS casks;
- Ghostty and AeroSpace registration with Launch Services;
- macOS `defaults` writes;
- shell, tmux, and Neovim startup on macOS;
- repeat setup runs and unmanaged-conflict backups; and
- the final `bin/check-macos` report.

Keep the existing tests:

- `just test-macos-portable` remains the fast link and conflict test.
- `just test-macos-container` remains the Linuxbrew compatibility test.
- `just test-macos-vm` becomes the slower Apple Silicon integration test run
  before macOS setup changes are merged or deployed.

This plan does not add hosted CI, build custom macOS images, test authentication,
or automate GUI interaction inside Ghostty or AeroSpace.

## Image policy

Start with the Cirrus Labs macOS Sequoia base image:

```text
ghcr.io/cirruslabs/macos-sequoia-base
```

The `base` variant includes Homebrew and the Tart Guest Agent. That lets the
harness use `tart exec` without SSH, passwords, or guest networking for command
transport. Xcode is not required by this repository, so the larger `xcode`
variant would waste download and disk space.

Pin a tested image tag or OCI digest in the harness. Do not make `latest` the
long-term default. Allow a temporary override:

```bash
TART_MACOS_IMAGE=<image-reference> just test-macos-vm
```

Image updates are deliberate maintenance changes. Run the full VM test before
committing a new pin.

## Source transfer and secret boundary

Test the current worktree, including uncommitted and untracked source files, so a
developer does not have to commit a change before testing it. Build the transfer
manifest from Git's tracked and non-ignored files. Skip deleted paths.

This is a fail-closed boundary:

- Git-ignored files never enter the staging archive.
- `.secrets*`, `.env*`, live agent settings, caches, and build output stay on the
  host.
- The harness does not mount the host checkout into the guest.
- The guest receives a writable copy because `bin/setup-macos` must seed its
  local settings files.
- A harness test inspects the transfer manifest and fails if any known sensitive
  path is present.

Stream the staged tree through standard input to avoid SSH and a persistent
shared directory. The intended transport is equivalent to:

```bash
tar -C "$staging_dir" -cf - . |
  tart exec -i "$vm_name" /bin/sh -c \
    'mkdir -p "$HOME/dotfiles" && tar -C "$HOME/dotfiles" -xf -'
```

## Proposed files and interface

### `bin/test-macos-tart`

Add one standalone Bash orchestrator with these responsibilities:

- require an Apple Silicon macOS host, Tart, Git, and enough free disk space;
- accept `--keep`, `--links-only`, and `--image <reference>`;
- create a collision-resistant VM name;
- clone the pinned base image and configure reasonable CPU and memory defaults;
- start `tart run --no-graphics` and capture its process ID and log;
- poll `tart exec` until the Guest Agent responds, with a bounded timeout;
- create and transfer the filtered worktree snapshot;
- invoke the guest test and preserve its exact exit code;
- stop the VM and delete only the disposable clone created by this run; and
- print commands for entering or deleting a VM retained by `--keep`.

Use a `trap` for cleanup. Cleanup must be idempotent and must never prune the
shared OCI cache or delete a pre-existing VM.

### `bin/test-macos-tart-guest`

Add a standalone guest-side test script. It runs from `/Users/admin/dotfiles`
and checks each stage before moving on:

1. Assert `uname -s` is `Darwin`, `uname -m` is `arm64`, and the checkout is
   exactly `$HOME/dotfiles`.
2. Run `bin/setup-macos` twice and verify representative links and seeded local
   settings.
3. Reproduce an unmanaged conflict, verify the ordinary run preserves it, then
   verify `--force` backs it up and restores the managed link.
4. In full mode, run `bin/install-macos-packages` and
   `bin/generate-portable-theme --check`.
5. Start Zsh, tmux, and Neovim in noninteractive/headless modes.
6. Run `bin/apply-macos-defaults` and read back representative boolean, integer,
   string, and path values with `defaults read`.
7. Run `bin/check-macos` and require a zero exit code.

`--links-only` stops after the setup and conflict checks. It provides a quicker
real-macOS test while developing link behavior.

### `Justfile`

Expose the harness only through root recipes:

```just
# Run the portable setup in a disposable Tart macOS VM
test-macos-vm *args:
    bin/test-macos-tart {{ args }}
```

The script owns VM lifecycle details. The recipe remains a thin public entry
point.

### `README.md`

Add a short "Clean macOS VM test" section with:

```bash
brew install openai/tools/tart
just test-macos-vm
just test-macos-vm --links-only
just test-macos-vm --keep
```

Document the initial image download size and the fact that subsequent clones use
cached copy-on-write storage. Point detailed behavior to this plan rather than
copying it into the README.

## Implementation batches

### Batch 1: manual spike

1. Install Tart on the host with `brew install openai/tools/tart`.
2. Clone the selected base image and start it with `--no-graphics`.
3. Confirm `tart exec` works and reports an `arm64` macOS guest.
4. Transfer a small tar stream into the guest.
5. Confirm Homebrew can install one formula and one harmless cask headlessly.
6. Stop and delete the clone.

Completion criterion: the base image supports Guest Agent execution, archive
transfer, Homebrew, and headless cask installation without SSH setup.

### Batch 2: lifecycle and transfer harness

1. Implement argument parsing, prerequisite checks, unique naming, startup
   timeout, logs, and cleanup.
2. Build the worktree snapshot from tracked and non-ignored files.
3. Add checks that live settings and secret patterns are absent from the archive.
4. Transfer the archive and run a trivial command from the copied checkout.
5. Exercise success, command failure, startup timeout, interruption, and `--keep`.

Completion criterion: every path returns the right exit code and leaves no VM
clone behind unless `--keep` was requested.

### Batch 3: guest integration test

1. Port the applicable assertions from `tests/macos-container-e2e.sh` rather than
   changing that Linux test's contract.
2. Add the real macOS, cask, Launch Services, and `defaults` checks.
3. Add links-only and full modes.
4. Run the full test twice from separate fresh clones to catch leaked host or VM
   state.

Completion criterion: both fresh runs pass, and the second run does not depend on
files produced by the first.

### Batch 4: repository interface and documentation

1. Add the root `just test-macos-vm` recipe.
2. Add the short README instructions and troubleshooting commands.
3. Record the tested Tart version and image reference in test output.
4. Run `just test-macos-portable`, `just test-macos-container`, and the new VM
   test.

Completion criterion: all three test levels pass and their responsibilities are
clear from `just --list` and the README.

## Failure diagnostics

Always print:

- Tart version;
- image reference;
- VM name;
- host and guest macOS versions;
- the failed guest stage; and
- the host path to the Tart run log.

With `--keep`, also print:

```bash
tart run <vm-name>
tart exec -t <vm-name> /bin/zsh
tart stop <vm-name>
tart delete <vm-name>
```

Do not print environment dumps, transferred file contents, agent settings, or
host paths unrelated to this repository.

## Acceptance criteria

The plan is complete when:

- one command runs the current non-ignored worktree on a disposable macOS VM;
- the guest satisfies the setup scripts' real `Darwin arm64` guards;
- no ignored or known sensitive file crosses into the guest;
- setup idempotency and conflict backup behavior pass;
- the full Brewfile, casks, shell, tmux, Neovim, defaults, and `check-macos` pass;
- failures return nonzero and leave enough diagnostics to reproduce them;
- normal completion and interruption remove the disposable clone; and
- the existing shell and Linux container tests continue to pass.

## Expected constraints

- The first base-image download is large, roughly tens of gigabytes.
- Full Homebrew and browser installation will take much longer than the link
  test and requires internet access.
- Launch Services checks prove that casks are installed and discoverable, not
  that their graphical interfaces behave correctly.
- Apple limits the number of additional macOS VM instances allowed on a Mac.
  This harness runs one disposable guest at a time.

## References

- [Tart repository and installation](https://github.com/openai/tart)
- [Tart quick start](https://tart.run/quick-start/)
- [Cirrus Labs macOS image templates](https://github.com/cirruslabs/macos-image-templates)
- [Apple Virtualization framework](https://developer.apple.com/documentation/virtualization)
