import type { On } from 'claude-code'
import { expect, test } from 'claude-code/testing'

type World = { cwd: string; now: number; ran: string[]; status: (string | undefined)[] }

// Stands for the engine: a shell whose folder a `cd` in the command moves.
function world(on: On): World {
  const seen: World = { cwd: '/code/moto', now: 0, ran: [], status: [] }
  on('session.root', () => ({ value: '/code/moto' }))
  on('session.cwd', () => ({ value: seen.cwd }))
  on('clock.now', () => ({ value: seen.now }))
  on('ui.status', ($, e) => {
    seen.status.push(e.text)
    return { value: undefined }
  })
  on('tool.call', ($, e) => {
    if (e.tool === 'Bash') {
      seen.ran.push(e.command)
      const moves = [...e.command.matchAll(/cd '?([^ '&]+)'?/g)]
      seen.cwd = moves.at(-1)?.[1] ?? seen.cwd
    }
    return { result: {} }
  })
  return seen
}

test('the command after one that left the folder gets a nudge', async ($, on) => {
  const seen = world(on)
  const left = await $.tool.call({ tool: 'Bash', command: 'cd /code/xylophone && ls' })
  expect(left.context).toBeUndefined()
  const ran = await $.tool.call({ tool: 'Bash', command: 'git status' })
  expect(ran.context?.[0]).toContain('ran in /code/xylophone')
  expect(seen.status.at(-1)).toBe('shell in /code/xylophone')
})

test('a command inside the folder runs untouched and quiet', async ($, on) => {
  const seen = world(on)
  const ran = await $.tool.call({ tool: 'Bash', command: 'cd /code/moto/roles && ls' })
  expect(ran.context).toBeUndefined()
  expect(seen.ran).toEqual(['cd /code/moto/roles && ls'])
})

test('after 5 idle minutes away, the next command starts back home', async ($, on) => {
  const seen = world(on)
  await $.tool.call({ tool: 'Bash', command: 'cd /code/xylophone' })
  seen.now = 4 * 60 * 1000
  await $.tool.call({ tool: 'Bash', command: 'git status' })
  expect(seen.ran.at(-1)).toBe('git status')
  seen.now += 5 * 60 * 1000
  const ran = await $.tool.call({ tool: 'Bash', command: 'git status' })
  expect(seen.ran.at(-1)).toBe("cd '/code/moto' && git status")
  expect(ran.context?.[0]).toContain('ran from /code/moto')
  expect(seen.status.at(-1)).toBeUndefined()
})

test('a command that starts by going home gets no nudge', async ($, on) => {
  const seen = world(on)
  await $.tool.call({ tool: 'Bash', command: 'cd /code/xylophone' })
  const ran = await $.tool.call({ tool: 'Bash', command: 'cd /code/moto && git status' })
  expect(ran.context).toBeUndefined()
  expect(seen.status.at(-1)).toBeUndefined()
})
