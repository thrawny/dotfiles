/**
 * ghostty-title - Simple Ghostty terminal title with AI session name.
 *
 * Sets the window title to: π · <project> · <ai-session-name>
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import path from "node:path";

function buildTitle(sessionName?: string): string {
  const segments: string[] = ["π", path.basename(process.cwd())];
  if (sessionName) segments.push(sessionName);
  return segments.join(" · ");
}

export default function (pi: ExtensionAPI) {
  pi.on("session_start", async (_event, ctx) => {
    if (!ctx.hasUI) return;
    const sessionName = pi.getSessionName();
    ctx.ui.setTitle(buildTitle(sessionName));
  });
}
