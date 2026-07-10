# Standalone HTML template

Every artifact needs a responsive viewport, content-specific title and description, matching Open Graph metadata, and a self-contained favicon.

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />

    <title>Human-readable artifact title</title>
    <meta name="description" content="One concise sentence describing the artifact." />

    <meta property="og:type" content="website" />
    <meta property="og:title" content="Human-readable artifact title" />
    <meta property="og:description" content="One concise sentence describing the artifact." />
    <link rel="icon" href="data:image/svg+xml,..." />

    <style>
      /* Self-contained styles */
    </style>
  </head>
  <body>
    <main>
      <h1>Artifact title</h1>
    </main>
  </body>
</html>
```

Use content-specific values rather than leaving generic placeholder text. Slack can build a basic unfurl from the title, description, and `og:*` fields.

Leave out `og:url` until the public URL is known; the publishing tool may add or override it. `og:image` is optional rather than required for a basic preview.

Prefer an inline SVG data URI for the favicon so the artifact remains one file. Use semantic elements and heading order so search, copy/paste, accessibility tools, and reader mode have useful structure.
