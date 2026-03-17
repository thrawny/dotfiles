---
name: wayvoice
description: Fix voice dictation misspellings by adding text replacements to wayvoice. Use when the user mentions a misspelling, mistranscription, or wrong word from voice input and wants it corrected for future dictation (e.g., "fix that misspelling", "it keeps saying X instead of Y", "add a replacement for...", "that word is wrong").
---

# wayvoice replacements

When the user reports a voice dictation misspelling, add a replacement rule so wayvoice auto-corrects it in future transcriptions.

## Command

```bash
wayvoice replace add <from> <to>           # Whole-word replacement
wayvoice replace add --substring <from> <to>  # Match inside words too
```

Rules are stored in `~/.config/wayvoice/config.toml`.

## Workflow

1. Identify the mistranscribed word (`from`) and the intended word (`to`) from context.
   - Look at the user's recent message for the misspelling. Often the correct word is obvious from context (e.g., "nicks" in a Nix discussion means "Nix").
   - If ambiguous, ask the user to confirm both words.
2. Decide whether `--substring` is needed:
   - Use `--substring` when the wrong text appears as part of other words (e.g., "nick's" → "Nix's" needs substring since "nick" appears inside "nick's").
   - Default to whole-word (no flag) for standalone words.
3. Run `wayvoice replace add [--substring] <from> <to>`.
4. Confirm the replacement was added.

## Examples

- User says "it wrote 'nicks' instead of 'Nix'":
  `wayvoice replace add nicks Nix`

- User says "fix that misspelling" after a message containing "I want to configure way voice":
  `wayvoice replace add "way voice" wayvoice`

- User says "'gifts' should be 'git'" but wants "gifts" as a standalone word left alone, only fixing inside compounds:
  Ask the user to clarify, then use `--substring` if appropriate.
