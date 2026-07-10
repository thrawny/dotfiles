# Publishing

Publish only after an explicit request to share, upload, create a public link, or send the artifact to Drops.

Before uploading, verify:

- the rendered file is the intended final artifact
- title and description are specific
- the filename or generated slug reveals nothing private
- no secrets, customer data, API keys, private URLs, or local-only assets are embedded

Publish with:

```bash
share-html path/to/artifact.html
```

The command publishes to Drops and prints the public URL. It derives the slug from the HTML title, falling back to the filename. Use `--slug` to override it, or `--url`/`DROPS_URL` for a different Drops deployment.

Return the resulting URL. Drops supports inline comment threads on selected text, making it suitable for review artifacts.
