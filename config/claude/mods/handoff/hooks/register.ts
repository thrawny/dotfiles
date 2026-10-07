import type { EngineInterface, Register } from 'claude-code'

// /handoff is a prompt command, so its work is the turn that starts after it runs.
let startedAt: number | undefined
let handoffTurn: string | undefined

async function handoffPath($: EngineInterface) {
  const { exitCode, stdout } = await $.process.run(['git', 'rev-parse', '--show-toplevel'])
  const root = exitCode === 0 ? stdout.trim() : await $.session.cwd()
  return `${root}/handoff.md`
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
    await $.command.run({ command: 'takeoff' })
  } catch (error) {
    $.ui.toast(`handoff stopped: ${error instanceof Error ? error.message : String(error)}`)
  }
}

export const register: Register = on => {
  on('command.run', { command: 'handoff' }, async ($, e, next) => {
    startedAt = await $.clock.now()
    handoffTurn = undefined
    return next(e)
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
