import type { On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

import type { Pass } from '../types'

type World = { runs: number; prompts: string[]; status: (string | undefined)[] }

// Answers every event the mod raises beneath it: each moto pass hands out the next
// of `passes`, then quiet ones.
function world(on: On, passes: Pass[], env: Record<string, string> = {}): World {
  const seen: World = { runs: 0, prompts: [], status: [] }
  mock.env(on, env)
  on('session.start', ($, e) => ({ cwd: e.cwd }))
  on('turn.start', ($, e) => ({ turnId: e.turnId }))
  on('turn.complete', ($, e) => ({ text: e.answer }))
  on('ui.status', ($, e) => {
    seen.status.push(e.text)
    return { value: undefined }
  })
  on('process.run', () => {
    seen.runs += 1
    const pass = passes.shift() ?? { watching: 1, lines: [], notes: null }
    const stdout = JSON.stringify(pass)
    return {
      value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false },
    }
  })
  on('prompt.submit', ($, e) => {
    seen.prompts.push(e.text)
    return { text: e.text }
  })
  return seen
}

const NEWS: Pass = { watching: 2, lines: ['abc-1 question: which?'], notes: null }
const MORE: Pass = { watching: 2, lines: ['abc-2: pane closed'], notes: '[job] Review widgets#7.' }

test('news reaches an idle driver as one tagged prompt', async ($, on) => {
  const clock = mock.clock(on)
  const seen = world(on, [NEWS])
  await $.session.start({ cwd: '/moto', surface: 'terminal', isInteractive: true })
  await clock.advance(3000)
  expect(seen.prompts).toEqual(['[moto watch]\nabc-1 question: which?'])
  expect(seen.status).toEqual(['watching 2'])
  await clock.advance(3000)
  expect(seen.prompts.length).toBe(1)
})

test('news and job notes found during a turn wait for its end', async ($, on) => {
  const clock = mock.clock(on)
  const seen = world(on, [NEWS, MORE])
  await $.session.start({ cwd: '/moto', surface: 'terminal', isInteractive: true })
  await $.turn.start({ text: 'hi', turnId: 't1' })
  await clock.advance(6000)
  expect(seen.runs).toBe(2)
  expect(seen.prompts).toEqual([])
  await $.turn.complete({
    answer: '',
    durationMs: 1,
    isAborted: false,
    turnId: 't1',
    reason: 'answer',
  })
  expect(seen.prompts).toEqual([
    '[moto watch]\nabc-1 question: which?\nabc-2: pane closed\n\n[job] Review widgets#7.',
  ])
})

test('a fork of the driver never polls', async ($, on) => {
  const clock = mock.clock(on)
  const seen = world(on, [NEWS], { MOTO_FORK: '1' })
  await $.session.start({ cwd: '/moto', surface: 'terminal', isInteractive: true })
  await clock.advance(9000)
  expect(seen.runs).toBe(0)
})
