// What one `moto watch --once` prints.
export type Pass = {
  state: 'news' | 'quiet' | 'idle' | 'busy'
  watching: number
  lines: string[]
}

declare module 'claude-code' {
  interface PluginState {
    // News a pass found while a turn ran, held for the turn's end.
    'moto-watch': { pending: readonly string[] }
  }
}
