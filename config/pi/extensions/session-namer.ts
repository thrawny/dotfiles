/**
 * session-namer - Auto-names sessions from the first user message.
 *
 * Emits pi.events "session:named" whenever the session name changes,
 * so other extensions (ghostty-title, tmux-window-name, etc.) can react.
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

export const SESSION_NAMED_EVENT = "session:named";

const MAX_NAME_LEN = 60;

function nameFromMessage(text: string): string {
  const oneline = text.replace(/\s+/g, " ").trim();
  if (oneline.length <= MAX_NAME_LEN) return oneline;
  const truncated = oneline.slice(0, MAX_NAME_LEN);
  const lastSpace = truncated.lastIndexOf(" ");
  return (lastSpace > MAX_NAME_LEN / 2 ? truncated.slice(0, lastSpace) : truncated) + "…";
}

const RENAME_AT = 5;

export default function (pi: ExtensionAPI) {
  let inputCount = 0;
  let done = false;

  function emitName() {
    pi.events.emit(SESSION_NAMED_EVENT, pi.getSessionName());
  }

  pi.on("session_start", async () => {
    done = !!pi.getSessionName();
    emitName();
  });

  pi.on("session_switch", async () => {
    done = !!pi.getSessionName();
    inputCount = 0;
    emitName();
  });

  pi.on("input", async (event) => {
    if (done || event.source !== "interactive") return;
    inputCount++;
    if (inputCount === 1 || inputCount === RENAME_AT) {
      pi.setSessionName(nameFromMessage(event.text));
      emitName();
      if (inputCount === RENAME_AT) done = true;
    }
  });
}
