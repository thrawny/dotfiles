---
name: wayvoice
description: Fix voice dictation misspellings by adding text replacements to wayvoice. Use when the user mentions a misspelling, mistranscription, or wrong word from voice input (e.g., "fix that misspelling", "it keeps saying X instead of Y", "add a replacement for..."). Also load this skill proactively when you notice words that look like voice mistranscriptions — real words that don't fit the technical context, such as common words where a technical term or proper noun was clearly intended (e.g., "nicks" for Nix, "way land" for Wayland, "home brew" for Homebrew).
---

# wayvoice replacements

When the user reports a voice dictation misspelling, add a replacement rule so wayvoice auto-corrects it in future transcriptions.

## Command

```bash
wayvoice replace add <from> <to>           # Whole-word replacement
wayvoice replace add --substring <from> <to>  # Match inside words too
```

Rules are stored in `~/.config/wayvoice/config.toml`.

## Proactive detection

The user dictates via voice, so watch for words that look like mistranscriptions — real words that don't fit the context. When you spot a likely voice error, fix it in your response AND suggest adding a wayvoice replacement so it doesn't recur. Examples of patterns to watch for:

- Technical terms transcribed as common words: "nicks" → Nix, "way voice" → wayvoice, "gifts" → git, "home brew" → Homebrew, "doc her" → Docker
- Proper nouns mangled into dictionary words: "clothes" → Claude, "answer ball" → Ansible
- Homophones or near-homophones that don't fit context: "their" → there, "weight" → wait (only when clearly wrong)

When you detect one: respond to the user's actual intent (interpreting the correct word), then suggest: "It looks like wayvoice transcribed X as Y — want me to add a replacement?"

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

- Agent notices user wrote "I need to update my nicks config" in a dotfiles repo:
  Respond about Nix config, then suggest: "It looks like wayvoice transcribed 'Nix' as 'nicks' — want me to add a replacement?"
