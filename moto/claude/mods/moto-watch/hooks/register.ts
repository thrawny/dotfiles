import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Pass } from '../types'

// Each pass is one short `moto watch --once`; the Stop hook counts the passes as a watch.
const POLL_MS = 3000
const TAG = '[moto watch]'
const SECTION = {
  id: 'moto-watch:watching',
  scope: 'session',
  text: [
    'The moto-watch mod watches the workers for this session, so never start `moto watch`.',
    `When a worker needs you, a prompt starting with ${TAG} arrives with one line per worker,`,
    'the lines `moto watch` would print. Act on them as the Watching section says.',
  ].join(' '),
} as const

const pending = atom({ plugin: 'moto-watch', key: 'pending' } as const, [] as readonly string[])

// Turns under way. News waits for the last to end, then arrives as one prompt.
const turns = new Set<string>()
let isPolling = false

async function deliver($: EngineInterface) {
  const lines = await read($, pending)
  if (turns.size > 0 || lines.length === 0) {
    return
  }
  await update($, pending, () => [])
  void $.prompt.submit({ text: [TAG, ...lines].join('\n') })
}

async function poll($: EngineInterface) {
  if (isPolling) {
    return
  }
  isPolling = true
  try {
    const { exitCode, stdout, stderr } = await $.process.run(['moto', 'watch', '--once'])
    if (exitCode !== 0) {
      $.ui.status(`moto watch: ${stderr.trim().split('\n')[0] || `exit ${exitCode}`}`)
      return
    }
    const pass = JSON.parse(stdout) as Pass
    $.ui.status(pass.watching > 0 ? `moto: watching ${pass.watching}` : undefined)
    if (pass.lines.length > 0) {
      await update($, pending, held => [...held, ...pass.lines])
    }
    await deliver($)
  } catch (error) {
    $.ui.status(`moto watch: ${error instanceof Error ? error.message : String(error)}`)
  } finally {
    isPolling = false
  }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const result = await next(e)
    // A fork of the driver owns no task; moto refuses to watch from one.
    if ((await $.env.get('MOTO_FORK')) === undefined) {
      $.clock.every(POLL_MS, () => void poll($))
    }
    return result
  })

  on('prompt.compose', async ($, e, next) => {
    const { sections } = await next(e)
    return { sections: [...sections, SECTION] }
  })

  on('turn.start', ($, e, next) => {
    turns.add(e.turnId)
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    turns.delete(e.turnId)
    await deliver($)
    return result
  })
}
