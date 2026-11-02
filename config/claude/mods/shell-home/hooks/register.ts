import type { EngineInterface, Register } from 'claude-code'

// A Bash call this long after the last one starts back in the session's folder.
const RETURN_AFTER_MS = 5 * 60 * 1000

const quote = (path: string) => `'${path.replaceAll("'", `'\\''`)}'`

// The shell's folder as the engine records it once a call's hooks are done, so a
// call reads where the calls before it left the shell.
async function away($: EngineInterface): Promise<{ cwd: string; root: string } | undefined> {
  const [cwd, root] = await Promise.all([$.session.cwd(), $.session.root()])
  return cwd === root || cwd.startsWith(`${root}/`) ? undefined : { cwd, root }
}

// Reset on reload, which only costs one missed return.
let lastBashAt: number | undefined

export const register: Register = on => {
  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    const now = await $.clock.now()
    const idle = lastBashAt !== undefined && now - lastBashAt >= RETURN_AFTER_MS
    lastBashAt = now
    const outside = await away($)
    // A command that starts by going home needs neither a nudge nor a return.
    const home = outside && e.command.match(/^\s*cd\s+'?([^\s'&;|]+)/)?.[1]
    if (outside && home && (home === outside.root || home.startsWith(`${outside.root}/`))) {
      $.ui.status(undefined)
      return next(e)
    }
    $.ui.status(outside && !idle ? `shell in ${outside.cwd}` : undefined)
    if (!outside) {
      return next(e)
    }
    const command = idle ? `cd ${quote(outside.root)} && ${e.command}` : e.command
    const ran = await next({ ...e, command })
    if (ran.deny !== undefined) {
      return ran
    }
    const note = idle
      ? `shell-home: the shell had stayed in ${outside.cwd}, so this command ran from ${outside.root}.`
      : `shell-home: this command ran in ${outside.cwd}, outside your task's folder ${outside.root}.` +
        ' cd back, or use git -C and absolute paths for other repos.'
    return { ...ran, context: [...(ran.context ?? []), note] }
  })
}
