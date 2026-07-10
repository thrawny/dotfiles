---
name: shareable-html
description: Build self-contained HTML artifacts ready for browser viewing and public-link previews. Use for standalone reports, infographics, mockups, visual explanations, dashboards, or HTML intended for live-html, share-html, or Slack.
---

# Shareable HTML

Create a polished local HTML artifact. Publishing is a separate, explicit branch.

## 1. Establish the artifact

Identify its subject, audience, purpose, and content. Load and follow the `frontend-design` skill before designing so the result has an intentional visual direction rather than a generic template.

This step is complete when the artifact has a concrete design direction and a specific title and description.

## 2. Build the local file

Read [HTML-TEMPLATE.md](HTML-TEMPLATE.md), then create one self-contained `.html` file in `./lab/` by default.

Prefer semantic static HTML and inline CSS. Keep basic viewing independent of JavaScript and network access; add progressive enhancement only when interactivity serves the artifact. Embed images as data URIs or explicitly plan companion files.

This step is complete when the file opens directly in a browser, adapts to mobile, preserves readable document structure, and includes all required metadata from the template.

## 3. Verify

Open or render the file and check:

- visual hierarchy and responsive layout
- keyboard focus and reduced-motion behavior where relevant
- title, description, favicon, and Open Graph metadata
- absence of secrets, customer data, private URLs, and accidental filename leakage

Fix observed rendering problems before presenting the local path.

## 4. Publish only on request

Local creation does not imply upload. When the user explicitly asks for a public link, upload, share, or Drops publication, read and follow [PUBLISHING.md](PUBLISHING.md).
