---
name: shareable-html
description: Create static HTML artifacts that are meant to be shared via live-html or public share links. Use this skill whenever building or editing standalone HTML reports, infographics, mockups, visual explanations, dashboards, or any agent-generated HTML likely to be published with share-html or pasted into Slack. Ensures good standalone rendering and Slack/Open Graph unfurls.
---

# Shareable HTML Artifacts

Use this skill when creating standalone HTML files that may be previewed with `live-html`, pasted into Slack, or shared with `share-html` only when the user explicitly asks to publish/share/upload it.

The goal is a local HTML file that works well as a direct browser page and is ready for shared link previews if the user later asks to publish it. Do not upload to drops or any public sharing destination by default.

## Design prerequisite

Before creating or editing the HTML file, load and follow the `frontend-design` skill. Shareable artifacts should be visually intentional, not just technically valid.

Use the frontend-design guidance to choose a clear aesthetic direction, typography, layout, color system, and visual rhythm before writing the HTML/CSS.

## Required `<head>` metadata

Every shareable HTML artifact should include content-specific metadata in the `<head>`:

```html
<title>Human-readable artifact title</title>
<meta name="description" content="One concise sentence describing the artifact." />

<meta property="og:type" content="website" />
<meta property="og:title" content="Human-readable artifact title" />
<meta property="og:description" content="One concise sentence describing the artifact." />
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'%3E%3Crect width='64' height='64' rx='14' fill='%2317150f'/%3E%3Cpath d='M32 8C22 20 16 29 16 39a16 16 0 0 0 32 0C48 29 42 20 32 8Z' fill='%2373c7ff'/%3E%3Cpath d='M25 42c5 4 13 3 17-3' fill='none' stroke='%23f5f0df' stroke-width='4' stroke-linecap='round' opacity='.85'/%3E%3C/svg%3E" />
```

Guidance:
- Do not include `og:url` unless the final public share URL is already known. The uploader/CLI can add or override deployment-specific URLs.
- `og:image` is not needed at this time for basic link previews.
- Include a favicon. Prefer an inline SVG/data URI favicon so the artifact stays self-contained and does not need companion files.

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

## File location

Put generated shareable HTML artifacts in `./lab/` by default. This directory is always gitignored and is the expected scratch space for agent-created previews, infographics, reports, and mockups.

## Publishing workflow

Default to local-only output. Creating or editing a shareable HTML artifact does **not** imply publishing it.

Only upload to drops or run a real `share-html` publish when the user explicitly asks to publish, share, upload, create a public link, or send it to drops.

When explicitly asked to publish/share an HTML artifact, use the `share-html` CLI available in path.

```bash
share-html path/to/artifact.html
```

It publishes the file to the drops app and prints the public share URL back.

The slug defaults to the HTML `<title>` (falling back to the filename); override it with `--slug`. Point at a different Drops deploy with `--url` or the `DROPS_URL` env var.

A published drop is more than a static page: viewers can select text in the rendered HTML and leave inline comment threads, so prefer it for review/feedback artifacts.

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
