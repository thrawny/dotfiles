---
name: wayvoice
description: >
  Run `wayvoice keyword add` or `wayvoice replace add` to teach voice dictation a new term or
  fix a recurring mistranscription. Load this skill at the moment you decide to add a keyword
  or replacement — its purpose is the exact command syntax, not detection.
  Trigger when: (1) the user says "add a wayvoice keyword/replacement", "fix that
  misspelling", "it keeps saying X instead of Y"; OR (2) you notice a mistranscription in the
  user's voice input (real English words wrong for context — "nicks"=Nix, "clothes"=Claude,
  "way land"=Wayland, "doc her"=Docker) and decide to correct it so it doesn't recur.
  Do not ask permission — just run the command inline and keep going with the original task.
  Not for wayvoice configuration, daemon setup, or microphone troubleshooting.
---

# wayvoice corrections

Two tools for fixing voice dictation: **keywords** (preventive) and **replacements** (reactive).

**Act silently.** When you spot a mistranscription, fix it in your reply AND run the wayvoice command in the same turn. Do not stop to ask "want me to add this?" — the whole point is to not break the user's flow. If the intended word is genuinely ambiguous from context, *then* ask; otherwise just do it.

## Keywords vs Replacements

- **Keywords** bias the transcription model toward recognizing a term correctly in the first place. Use for proper nouns, technical terms, and project-specific vocabulary the model hasn't seen.
- **Replacements** fix text after transcription via find-and-replace. Use when the model consistently produces a specific wrong word.

Prefer keywords when the term is a real word the model should learn to recognize (e.g., "Ghostty", "pnpm", "Groq"). Use replacements when the model produces a completely wrong word that needs mapping (e.g., "nicks" → "Nix").

When in doubt, add both — a keyword to help future transcriptions and a replacement to catch existing errors.

## Commands

```bash
wayvoice keyword add <word>                   # Bias transcription toward this term
wayvoice replace add <from> <to>              # Whole-word replacement
wayvoice replace add --substring <from> <to>  # Match inside words too
```

Config is stored in `~/.config/wayvoice/config.toml`.

## Workflow

1. Identify the mistranscribed word and the intended word from context. Only ask the user if genuinely ambiguous.
2. Decide what to add:
   - **Keyword**: proper noun or technical term the model should learn (e.g., "Terraform", "Kubernetes", "Ghostty").
   - **Replacement**: model produces a specific wrong word that needs correcting (e.g., "nicks" → "Nix").
   - **Both**: keyword for future prevention, replacement for current correction.
3. For replacements, decide if `--substring` is needed:
   - Use `--substring` when the wrong text appears inside other words (e.g., "nick's" → "Nix's").
   - Default to whole-word (no flag) for standalone words.
4. Run the command(s), note it briefly in your reply (one line), and continue the original task.

## Examples

- User says "it wrote 'nicks' instead of 'Nix'":
  `wayvoice replace add nicks Nix`

- User mentions a new tool "Ghostty" the model doesn't know:
  `wayvoice keyword add Ghostty`

- User says "fix that misspelling" after a message containing "I want to configure way voice":
  `wayvoice replace add "way voice" wayvoice`

- Agent notices "cooper nets" for Kubernetes:
  `wayvoice keyword add Kubernetes && wayvoice replace add "cooper nets" Kubernetes`

- Agent notices user wrote "I need to update my nicks config" in a dotfiles repo:
  Respond about Nix config as if the word were correct, run `wayvoice replace add nicks Nix` in the same turn, and note it in one line (e.g., "Added nicks→Nix replacement.").
