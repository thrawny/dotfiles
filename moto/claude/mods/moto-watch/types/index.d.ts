// What one `moto watch` prints.
export type Pass = {
  watching: number
  lines: string[]
  notes: string | null
}

declare module 'claude-code' {
  interface PluginState {
    // What passes found while a turn ran, held for the turn's end: worker lines and job notes.
    'moto-watch': { lines: readonly string[]; notes: readonly string[] }
  }
}
