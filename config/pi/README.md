# Pi extensions

Local extensions load from this directory's `extensions/` folder through the mutable `~/.pi/agent` symlink. Run `/reload` in Pi after editing them.

## Cancel and edit

`cancel-edit.ts` makes an early Escape stop generation, rewind the attempt, and put the original prompt back in the editor. It follows Pi's configured interrupt key and leaves autocomplete and dialog cancellation alone.

It only restores a text-only prompt during the first response, before any tool starts. Images, queued messages, an existing editor draft, and later turns keep normal cancellation. The abandoned attempt remains in saved history but leaves the active model context. `/cancel-edit` also invokes the action directly.

Requires Pi 0.87.1 or newer. See [AGENTS.md](AGENTS.md) for development checks.
