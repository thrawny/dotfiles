# M1 OpenClaw node

The M1 runs a headless companion for the existing gateway. Home Manager owns
`org.nix-community.home.openclaw-node`; activate changes with `just switch-hm`.
The laptop must be awake and logged in. Telegram remains on the gateway.

The service advertises `system.run.prepare`, `system.run`, `system.which` and
`system.execApprovals.get`. The read-only policy query lets the gateway recognize
local executable allowances; remote policy writes stay disabled. Local execution approvals
are separate from gateway pairing and command approval. Preserve `~/.openclaw`
when rebuilding: it holds the device identity and durable paired credential.
Do not copy the gateway's provider credentials or administrator token to the Mac.

Enrollment uses a short-lived node setup code minted by the existing gateway.
For a loopback gateway behind an existing HTTPS proxy, the supported
`device.pair.setupCode` RPC accepts `publicUrl` and `bootstrapProfile: "node"`.
Run the pinned CLI once with `node run --pair` and the same command list as the
service, then stop that foreground process before activating Home Manager.
Keep the setup code private; never save it in launchd arguments or source.

Before enrollment, configure local approvals through `openclaw approvals set`:
use `security: "allowlist"`, `ask: "on-miss"`, `askFallback: "deny"` and
`autoAllowSkills: false`. These are runtime permissions in SQLite, rather than
the immutable Nix configuration. Review individual command grants as needed.

For commands needing approval, the shared agent sends native approval requests
to the configured operator's Telegram DM. The private service EnvironmentFile
provides `OPENCLAW_TELEGRAM_EXEC_APPROVER`; group membership alone never grants
approval rights. Native approval buttons use the existing Telegram DM capability.

Invoke user-installed commands through the node's `PATH` (for example, `sonos`).
This version accepts approval requests for that form, while it rejects an
absolute writable executable path inside the node shell tool. A remembered
approval can be limited to the command and arguments shown in the request;
it does not necessarily allow every operation of that CLI. Verify the complete
request, operator decision and node result from Telegram before claiming that
interaction works. Headless CLI agent probes cannot wait for human approval.

Inspect the service with:

```sh
launchctl print gui/$(id -u)/org.nix-community.home.openclaw-node
```

Logs are in `~/Library/Logs/openclaw-node/node.log`. Use the gateway's
`openclaw-admin nodes status` to verify connection and approved capabilities.
The CLI's `node status` targets its own installer label, rather than this
Home Manager service. Pairing alone does not grant Telegram access or place a
chat's agent execution on the M1.
