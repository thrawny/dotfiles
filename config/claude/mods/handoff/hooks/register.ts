import type { EngineInterface, Register } from 'claude-code'

const STAY = '--stay'
const HANDOFF_FILE = 'Handoff file:'

// /handoff is a prompt command, so its work is the turn that starts after it runs.
let startedAt: number | undefined
let handoffTurn: string | undefined

// Takeoff runs in this session after /clear, so the handoff lives at the session's
// root, wherever the agent cd'd or whichever repo it worked in.
async function handoffPath($: EngineInterface) {
  const root = await $.session.root()
  const { exitCode, stdout } = await $.process.run(['git', 'rev-parse', '--show-toplevel'], { cwd: root })
  return `${exitCode === 0 ? stdout.trim() : root}/handoff.md`
}

// Clears only when this handoff wrote handoff.md, so a failed one keeps the session.
async function takeOff($: EngineInterface, since: number) {
  const path = await handoffPath($)
  const isWritten = (await $.fs.exists(path)) && (await $.fs.stat(path)).mtimeMs >= since
  if (!isWritten) {
    $.ui.toast(`No new ${path}, so the session stays as it is.`)
    return
  }
  try {
    await $.command.run({ command: 'clear' })
    await $.command.run({ command: 'takeoff', args: path })
  } catch (error) {
    $.ui.toast(`handoff stopped: ${error instanceof Error ? error.message : String(error)}`)
  }
}

export const register: Register = on => {
  // The old handoff goes first, so the agent writes a fresh one instead of editing it.
  // `--stay` writes the handoff and keeps the session; the command never sees the flag.
  // The command gets the path instead, so the agent writes where takeoff reads.
  on('command.run', { command: 'handoff' }, async ($, e, next) => {
    const path = await handoffPath($)
    await $.process.run(['rm', '-f', '--', path])
    const words = e.args.split(/\s+/).filter(word => word !== '')
    const isStaying = words.includes(STAY)
    startedAt = isStaying ? undefined : await $.clock.now()
    handoffTurn = undefined
    const goal = words.filter(word => word !== STAY).join(' ')
    return next({ ...e, args: `${HANDOFF_FILE} ${path}\n\n${goal}`.trimEnd() })
  }).catch(($, e, next) => next(e))

  on('turn.start', ($, e, next) => {
    if (startedAt !== undefined && handoffTurn === undefined) {
      handoffTurn = e.turnId
    }
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    if (e.turnId !== handoffTurn || startedAt === undefined) {
      return result
    }
    const since = startedAt
    startedAt = handoffTurn = undefined
    if (e.reason === 'answer') {
      // A hook the turn waits on may not run commands, so the chain starts after it.
      $.clock.after(0, () => void takeOff($, since))
    }
    return result
  })
}
