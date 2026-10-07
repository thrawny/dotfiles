import type { On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

type World = { commands: string[]; args: string[]; toasts: string[]; removed: string[] }

// The engine beneath the mod: /handoff writes handoff.md at `writes` (or never),
// and every other command just records its name.
function world(on: On, writes: number | null): World {
  const seen: World = { commands: [], args: [], toasts: [], removed: [] }
  on('command.run', ($, e) => {
    seen.commands.push(e.command)
    seen.args.push(e.args)
    return {}
  })
  on('turn.start', ($, e) => ({ turnId: e.turnId }))
  on('turn.complete', ($, e) => ({ text: e.answer }))
  on('process.run', ($, e) => {
    if (e.argv[0] === 'rm') {
      seen.removed.push(`${e.argv.at(-1)} before ${seen.commands.length} commands`)
    }
    return {
      value: { exitCode: 0, stdout: '/repo\n', stderr: '', isStdoutTruncated: false, isStderrTruncated: false },
    }
  })
  on('fs.exists', () => ({ value: writes !== null }))
  on('fs.stat', () => ({ value: { kind: 'file', size: 1, mtimeMs: writes ?? 0, isLink: false } }))
  on('ui.toast', ($, e) => {
    seen.toasts.push(e.text)
    return { value: undefined }
  })
  return seen
}

// /handoff as the person types it.
const TYPED = {
  command: 'handoff',
  args: '',
  origin: { kind: 'composer' },
  presentation: { isFullscreen: true, columns: 120 },
} as const

function ended(turnId: string, reason: 'answer' | 'aborted' = 'answer') {
  return { answer: '', durationMs: 1, isAborted: reason === 'aborted', turnId, reason } as const
}

test('a finished handoff clears the session and takes off', async ($, on) => {
  const clock = mock.clock(on, { now: 1000 })
  const seen = world(on, 2000)
  await $.command.run(TYPED)
  await $.turn.start({ text: 'Hand off', turnId: 't1' })
  await $.turn.complete(ended('t1'))
  await clock.advance(0)
  expect(seen.commands).toEqual(['handoff', 'clear', 'takeoff'])
})

test('the old handoff is removed before the command runs', async ($, on) => {
  const seen = world(on, 2000)
  await $.command.run({ ...TYPED, args: '--stay' })
  expect(seen.removed).toEqual(['/repo/handoff.md before 0 commands'])
})

test('a handoff that wrote nothing keeps the session', async ($, on) => {
  const clock = mock.clock(on, { now: 1000 })
  const seen = world(on, 500)
  await $.command.run(TYPED)
  await $.turn.start({ text: 'Hand off', turnId: 't1' })
  await $.turn.complete(ended('t1'))
  await clock.advance(0)
  expect(seen.commands).toEqual(['handoff'])
  expect(seen.toasts).toEqual(['No new /repo/handoff.md, so the session stays as it is.'])
})

test('an interrupted handoff keeps the session', async ($, on) => {
  const clock = mock.clock(on, { now: 1000 })
  const seen = world(on, 2000)
  await $.command.run(TYPED)
  await $.turn.start({ text: 'Hand off', turnId: 't1' })
  await $.turn.complete(ended('t1', 'aborted'))
  await clock.advance(0)
  expect(seen.commands).toEqual(['handoff'])
})

test('other turns never take off', async ($, on) => {
  const clock = mock.clock(on, { now: 1000 })
  const seen = world(on, 2000)
  await $.turn.start({ text: 'hi', turnId: 't1' })
  await $.turn.complete(ended('t1'))
  await clock.advance(0)
  expect(seen.commands).toEqual([])
})

test('--stay hands off without clearing, and the command never sees the flag', async ($, on) => {
  const clock = mock.clock(on, { now: 1000 })
  const seen = world(on, 2000)
  await $.command.run({ ...TYPED, args: 'ship the fix --stay' })
  await $.turn.start({ text: 'Hand off', turnId: 't1' })
  await $.turn.complete(ended('t1'))
  await clock.advance(0)
  expect(seen.commands).toEqual(['handoff'])
  expect(seen.args).toEqual(['ship the fix'])
})
