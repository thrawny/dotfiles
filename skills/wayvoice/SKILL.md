---
name: wayvoice
description: >
  Detect and fix voice dictation errors by adding wayvoice keywords and text replacements.
  DIRECT: Any mention of fixing a misspelling, typo, mistranscription, or wrong word — even
  terse "fix that misspelling" with no context. Also "it keeps saying X instead of Y".
  PROACTIVE: The user dictates via voice. ALWAYS trigger when you notice real English words
  that don't fit the technical context — these are voice errors. Watch for: technical terms as
  common words ("nicks"=Nix, "gifts"=git, "home brew"=Homebrew, "doc her"=Docker, "post
  gress"=Postgres), split words ("way land"=Wayland), proper nouns as dictionary words
  ("clothes"=Claude). If a word is valid English but wrong for the programming domain, assume
  voice error and trigger this skill.
  Not for wayvoice configuration or microphone setup.
---

# wayvoice corrections

Two tools for fixing voice dictation: **keywords** (preventive) and **replacements** (reactive).

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

## Proactive detection

The user dictates via voice, so watch for words that look like mistranscriptions — real words that don't fit the context. When you spot a likely voice error, fix it in your response AND suggest adding a wayvoice replacement so it doesn't recur. Examples of patterns to watch for:

- Technical terms transcribed as common words: "nicks" → Nix, "way voice" → wayvoice, "gifts" → git, "home brew" → Homebrew, "doc her" → Docker
- Proper nouns mangled into dictionary words: "clothes" → Claude, "answer ball" → Ansible
- Homophones or near-homophones that don't fit context: "their" → there, "weight" → wait (only when clearly wrong)

When you detect one: respond to the user's actual intent (interpreting the correct word), then suggest adding a keyword and/or replacement.

## Workflow

1. Identify the mistranscribed word and the intended word from context.
   - If ambiguous, ask the user to confirm.
2. Decide what to add:
   - **Keyword**: if the correct term is a proper noun or technical term the model should learn (e.g., "Terraform", "Kubernetes", "Ghostty").
   - **Replacement**: if the model produces a specific wrong word that needs correcting (e.g., "nicks" → "Nix").
   - **Both**: when appropriate — keyword for future prevention, replacement for current correction.
3. For replacements, decide if `--substring` is needed:
   - Use `--substring` when the wrong text appears inside other words (e.g., "nick's" → "Nix's").
   - Default to whole-word (no flag) for standalone words.
4. Run the commands and confirm.

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
  Respond about Nix config, then suggest: "It looks like wayvoice transcribed 'Nix' as 'nicks' — want me to add a keyword and replacement?"
