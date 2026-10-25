# Blueprint previews

Requires Bun 1.3+ and Portless on PATH. D2 is optional: diagrams stay readable as source when it is unavailable. Bun fetches pinned JavaScript dependencies into its cache on first use.

```sh
blueprint-serve ./lab                         # local Portless URL
blueprint-serve ./lab --name designs          # stable hostname
blueprint-serve ./lab --name designs --tailscale
blueprint-serve ./lab --port 4321             # direct loopback server, no Portless
blueprint-html lab/flow.blueprint.md          # standalone lab/flow.html
```

The index recursively lists Markdown and HTML files, newest first, with search by title, path, and description. Documents have links such as `/docs/reviews/auth/`. Their relative paths determine the URLs; changing a title keeps the link. When a Markdown source and matching HTML export coexist, the source appears once. Other filename collisions remain accessible under `/source/<filename>`.

Saving, adding, or removing a file refreshes open pages and the index. Refresh preserves scroll position, URL fragments, and the index search. Relative images, stylesheets, and document links resolve against the source directory. Hidden directories, dependency directories, and external symlinks are excluded; serve a directory containing only material you intend to expose, including its assets.

Tailscale sharing is opt-in even on hosts where Portless normally enables it. The server binds to loopback; Portless manages the named URL and optional tailnet registration. Ctrl-C stops the server and lets Portless remove its registration.

`--link-base https://github.com/<owner>/<repo>/blob/<commit>/` works with either command and turns source citations into links. The [source format](../skills/blueprint/ARTIFACT-FORMAT.md) defines frontmatter and typed fences.

The Bun implementation lives in `bin/blueprint/`. Page colors come from `applications.blueprint` in the [central theme](../nix/themes/monokai.json), using the published Home Manager copy when running from the Nix store. `BLUEPRINT_THEME` can select another copy of that document.
