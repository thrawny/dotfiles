import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Pass } from '../types'

// Each pass is one short `moto watch`, which hands over what changed since the last.
const POLL_MS = 3000
const TAG = '[moto watch]'
const SECTION = {
  id: 'moto-watch:watching',
  scope: 'session',
  text: [
    'The moto-watch mod runs `moto watch` every 3 seconds for this session, so never run it yourself:',
    'a pass hands its news over once. When a worker needs you, a prompt starting with',
    `${TAG} arrives after your turn, with one line per worker. Notes from scheduled jobs`,
    'arrive in the same prompt, each starting with [job].',
  ].join(' '),
} as const

const lines = atom({ plugin: 'moto-watch', key: 'lines' } as const, [] as readonly string[])
const notes = atom({ plugin: 'moto-watch', key: 'notes' } as const, [] as readonly string[])

// Turns under way. News waits for the last to end, then arrives as one prompt.
const turns = new Set<string>()
let isPolling = false

async function deliver($: EngineInterface) {
  if (turns.size > 0) {
    return
  }
  const held = await read($, lines)
  const left = await read($, notes)
  if (held.length === 0 && left.length === 0) {
    return
  }
  await update($, lines, () => [])
  await update($, notes, () => [])
  const parts = held.length > 0 ? [[TAG, ...held].join('\n'), ...left] : left
  void $.prompt.submit({ text: parts.join('\n\n') })
}

async function poll($: EngineInterface) {
  if (isPolling) {
    return
  }
  isPolling = true
  try {
    const { exitCode, stdout, stderr } = await $.process.run(['moto', 'watch'])
    if (exitCode !== 0) {
      $.ui.status(`moto watch: ${stderr.trim().split('\n')[0] || `exit ${exitCode}`}`)
      return
    }
    const pass = JSON.parse(stdout) as Pass
    $.ui.status(pass.watching > 0 ? `moto: watching ${pass.watching}` : undefined)
    if (pass.lines.length > 0) {
      await update($, lines, before => [...before, ...pass.lines])
    }
    const note = pass.notes
    if (note !== null) {
      await update($, notes, before => [...before, note])
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
