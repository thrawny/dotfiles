# Obelisk

## Deploy

From the dotfiles repository root, outside the agent sandbox:

```sh
just nix::deploy obelisk
```

This deploys the pinned NixOS configuration, including system packages and
Home Manager for `thrawny`. It can restart services. If a live switch is blocked,
the recipe installs the next boot generation and asks before rebooting.

To validate without deploying:

```sh
just nix::eval-host obelisk
just nix::build-host obelisk
```

## Herdr remote sessions

Herdr, Codex, Claude Code, and Pi are installed for `thrawny`, with the shared
agent configs, skills, and Herdr keybindings. Authenticate the agents as
`thrawny` on Obelisk before using them. The `t3code` and bot service accounts
have separate homes and credentials; this configuration does not copy them.

Use a local Herdr built from the same flake pin as Obelisk. From a machine with
Tailscale access:

```sh
ssh thrawny@obelisk
# Exit after verifying access and authenticating the agents.
herdr --remote ssh://thrawny@obelisk --session agents
```

Herdr starts or reattaches to the named server through SSH. There is no public
Herdr port or separate system service. `thrawny` has lingering enabled, and
logind does not kill user processes on logout.

Detach with `Ctrl+a`, then `q`. Run the same remote command to reattach.
To test persistence, leave a shell running `sleep 600`, detach, reconnect, and
check that the same pane is still running. A reboot stops running processes;
it is not equivalent to detaching.

Manage sessions from an SSH shell as `thrawny`:

```sh
herdr session list
herdr session stop agents
```

Stopping a session also stops its panes and agents.

## T3 Code and Astra

The server settings register `gpt-6-astra` with Codex and select it for text
generation. Codex's shared configuration also defaults to Astra.

The upstream T3 Code package remains unpatched. It still prefers Sol for new
threads, independently of Codex's default. Choose Astra as the project default
in T3 Code's UI when you want new threads to use it. Existing thread selections
are not changed by deployment.
