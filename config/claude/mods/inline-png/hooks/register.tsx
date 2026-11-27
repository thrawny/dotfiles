import type { EngineInterface, Register } from 'claude-code'

// Inside Herdr, Claude Code only draws images with CLAUDE_CODE_FORCE_TERMINAL_IMAGES=1:
// Herdr answers the terminal probe as libghostty, which Claude Code does not trust for images.

// Base64 PNG per path, so a redraw does not read the file again.
const cache = new Map<string, string | null>()

type Call = { tool: string; input: unknown; isRunning: boolean; isErrored: boolean; isInterrupted: boolean }

/** The path of a finished, successful Read of a .png, or undefined. */
function pngPath(c: Call): string | undefined {
  if (c.tool !== 'Read' || c.isRunning || c.isErrored || c.isInterrupted) return undefined
  const path = (c.input as { file_path?: unknown } | undefined)?.file_path
  return typeof path === 'string' && path.toLowerCase().endsWith('.png') ? path : undefined
}

async function load($: EngineInterface, path: string) {
  let png = cache.get(path)
  if (png === undefined) {
    try {
      png = (await $.fs.read(path, { as: 'bytes' })).base64
    } catch {
      png = null
    }
    cache.set(path, png)
  }
  return png
}

export const register: Register = (on) => {
  // A standalone or unfolded Read row.
  on('ui.render', { component: 'ToolUse' }, async ($, e, next) => {
    const row = await next(e)
    if (e.surface !== 'terminal') return row
    const path = pngPath(e.props)
    const png = path && (await load($, path))
    if (!path || !png) return row
    const { Box, Image } = $.ui.resolve(e)
    return (
      <Box flexDirection="column">
        {row}
        <Box paddingLeft={2}>
          <Image source={{ png }} columns={48} rows={14} alt={`[image: ${path}]`} />
        </Box>
      </Box>
    )
  })

  // A folded group ("Read 1 file"): keep the count line, draw each PNG under it.
  on('ui.render', { component: 'ToolGroup' }, async ($, e, next) => {
    const row = await next(e)
    if (e.surface !== 'terminal' || e.props.isExpanded) return row
    const shots: { path: string; png: string }[] = []
    for (const c of e.props.calls) {
      const path = pngPath(c)
      const png = path && (await load($, path))
      if (path && png) shots.push({ path, png })
    }
    if (shots.length === 0) return row
    const { Box, Image } = $.ui.resolve(e)
    return (
      <Box flexDirection="column">
        {row}
        {shots.map((s, i) => (
          <Box key={`png-${i}`} paddingLeft={2}>
            <Image key={`img-${i}`} source={{ png: s.png }} columns={48} rows={14} alt={`[image: ${s.path}]`} />
          </Box>
        ))}
      </Box>
    )
  })
}
