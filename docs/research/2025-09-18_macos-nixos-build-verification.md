# Research: Verifying the NixOS flake from macOS

## Goal

Show how far we can validate `nix/flake.nix` on macOS before touching a real NixOS machine, using the new `nix/hosts/tester` target for dry runs and a remote builder when needed.

## Prerequisites

- Nix with flakes enabled on macOS (the repo already assumes this).
- Dotfiles repo checked out at `~/dotfiles` so the flake’s path assumptions stay valid.
- Optional: access to an `x86_64-linux` builder reachable via SSH (`linux-builder` in the examples below).

## 1. Quick syntax/evaluation checks

Most mistakes surface by evaluating the system without building the closure:

```bash
cd ~/dotfiles/nix
nix flake check
```

- Fails fast on syntax/module errors.
- When `flake check` has no custom tests, the real work is still the `nixosSystem` evaluation.

## 2. Dry-run the tester host (no remote builder required)

macOS is `*-darwin`, so allow cross-building to the tester’s Linux platform and relax the “unsupported system” gate:

```bash
NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 \
  NIXPKGS_ALLOW_BROKEN=1 \
  nix build --dry-run .#nixosConfigurations.tester.config.system.build.toplevel
```

Notes:

- `--dry-run` stops after ensuring every derivation can be realised. Great for catching syntax/module mistakes with no Linux host.
- The tester host ships with a tmpfs-based `hardware-configuration.nix`, so there is no root-filesystem warning during evaluation.

## 3. Configure an external builder (optional but recommended)

When you want to materialise the closure:

1. Add the builder to `~/.config/nix/nix.conf` (or export `NIX_BUILDERS` before the command):

   ```ini
   builders = ssh-ng://builder@linux-builder aarch64-linux /etc/nix/builder_ed25519 4 - - -
   ```

   - Replace the host/key tuple with the right identity file and jobs.
   - Leave the system field as `x86_64-linux` if your builder is x86_64.

2. Ensure the builder trusts your public key (`nix copy-id` or manual `authorized_keys`).

3. Re-run the build without `--dry-run`:

   ```bash
   NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 \
     NIXPKGS_ALLOW_BROKEN=1 \
     nix build .#nixosConfigurations.tester.config.system.build.toplevel
   ```

What to expect:

- macOS orchestration streams derivations to `linux-builder`; the first run can take 10–20 minutes.
- The output path looks like `/nix/store/<hash>-nixos-system-tester-<date>`; the build leaves a `result` symlink under `nix/` when it finishes.
- If your local command times out, SSH to the builder and run the same command directly there to finish the job.

## 4. Remote-only confirmation (when macOS timeouts are inconvenient)

SSH into the builder and run the flake from the shared checkout:

```bash
ssh builder@linux-builder
cd ~/dotfiles/nix
nix build .#nixosConfigurations.tester.config.system.build.toplevel
```

- This avoids SSH session timeouts on macOS and uses the builder’s native system string.
- Copy the resulting `/nix/store/...` closure or the `result` symlink back if you need it locally.

## 5. Verifying Home Manager activation logic

The dry-run/build steps ensure the activation DAG compiles. To confirm the example seeding logic quickly:

```bash
nix eval --expr '\n  let\n    cfg = (builtins.getFlake ".").nixosConfigurations.tester;\n  in cfg.config.home-manager.users.jonas.home.activation.seedClaudeSettings.text\n'
```

- Replace the attribute path if you renamed the host/user.
- The command prints the shell snippet that Home Manager will run before link generation; useful to confirm the repo paths look right.

## 6. Troubleshooting

- **Timeouts on macOS** – the CLI wrapper times out after ~20 minutes. Either re-run with `nix build` directly on the builder or split the job by first copying derivations via `--dry-run` and then finishing onsite.
- **`Failed to find a machine for remote build`** – update the builder’s `system` string in `nix.conf` so it matches the tester’s `x86_64-linux` host platform.
- **`Package … is marked as broken`** – keep `NIXPKGS_ALLOW_BROKEN=1` for iterative work. Remove it before production builds to catch regressions.
- **Missing root filesystem** – the tester hardware module already supplies a tmpfs root, so the evaluation never complains even on macOS.

## TL;DR

- `nix flake check --impure` and the `--dry-run` build catch almost all issues from macOS.
- For a real closure, reuse the same command with a remote Linux builder or run the build on that machine directly.
