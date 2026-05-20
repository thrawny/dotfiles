---
name: shareable-html
description: Create static HTML artifacts that are meant to be shared via live-html or public share links. Use this skill whenever building or editing standalone HTML reports, infographics, mockups, visual explanations, dashboards, or any agent-generated HTML likely to be published with share-html or pasted into Slack. Ensures good standalone rendering and Slack/Open Graph unfurls.
---

# Shareable HTML Artifacts

Use this skill when creating standalone HTML files that may be shared with `share-html`, previewed with `live-html`, or pasted into Slack.

The goal is a file that works well both as a direct browser page and as a shared link preview.

## Required `<head>` metadata

Every shareable HTML artifact should include content-specific metadata in the `<head>`:

```html
<title>Human-readable artifact title</title>
<meta name="description" content="One concise sentence describing the artifact." />

<meta property="og:type" content="website" />
<meta property="og:title" content="Human-readable artifact title" />
<meta property="og:description" content="One concise sentence describing the artifact." />
```

Guidance:
- Make the title specific, not generic: `Sinexcel Modbus Infographic`, not `Report`.
- Keep descriptions under roughly 160 characters.
- Describe what the viewer will get, not implementation details.
- Do not include `og:url` unless the final public share URL is already known. The uploader/CLI can add or override deployment-specific URLs.
- `og:image` is not needed at this time for basic link previews.

## Slack unfurl expectations

Slack uses the page title, description, and Open Graph tags for previews. For a basic unfurl, title + description + `og:*` tags are enough. `og:image` is not needed at this time for basic link previews.

## Standalone HTML requirements

Prefer a single self-contained `.html` file:
- Inline CSS in a `<style>` tag.
- Avoid external JS and external assets unless the user specifically asks for them.
- If images are needed, use data URIs or plan for companion uploads.
- Make it responsive with `<meta name="viewport" content="width=device-width, initial-scale=1" />`.
- Use semantic structure (`main`, `section`, headings) so browser reader mode, search, copy/paste, and accessibility work reasonably.

## JavaScript posture

For shareable HTML, assume JavaScript may be allowed during testing but should not be required for basic viewing.

Prefer:
- static HTML/CSS for infographics and reports
- progressive enhancement only when interactivity is valuable
- no network calls from the artifact unless explicitly requested

## Publishing workflow

When asked to publish/share an HTML artifact, use the `share-html` CLI from the dotfiles repo if available:

```bash
share-html path/to/artifact.html
```

It uploads the file and prints the public share URL.

If the artifact is not ready for publishing yet, use:

```bash
share-html --dry-run path/to/artifact.html
```

## Checklist before sharing

Before publishing, quickly verify:

- `<title>` is present and specific.
- `meta name="description"` is present.
- `og:type`, `og:title`, and `og:description` are present.
- Page renders without a local dev server.
- The filename/slug will not leak sensitive information.
- No secrets, customer data, API keys, or private URLs are embedded.

## Example

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Sinexcel Modbus Infographic</title>
    <meta
      name="description"
      content="A visual summary of Sinexcel Modbus registers, polling flow, and data mapping."
    />
    <meta property="og:type" content="website" />
    <meta property="og:title" content="Sinexcel Modbus Infographic" />
    <meta
      property="og:description"
      content="A visual summary of Sinexcel Modbus registers, polling flow, and data mapping."
    />
    <style>
      body { font-family: system-ui, sans-serif; }
    </style>
  </head>
  <body>
    <main>
      <h1>Sinexcel Modbus Infographic</h1>
    </main>
  </body>
</html>
```
