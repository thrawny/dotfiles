# Plan: an API view on the review page

Status: planned, not started.

## Goal

The review page gets a second way to read a pull request. Besides the line
diff, it shows a diff of what each changed module exports, without function
bodies. A reviewer then sees first how a change affects other code, and reads
the bodies second.

The model is the API state in [codediff.nvim](https://github.com/thrawny/codediff.nvim)
(`lua/codediff/api/`), which does this in Neovim for Go, Python and
TypeScript. Mission control works on its own: it never calls Neovim.

## Decision

Each language reads its own API with its own toolchain. Mission control can
run `go` and `python3`.

| Language   | Tool                                                                                                                                                                                              |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Go         | A small Go program. `go/parser` and `go/doc` find the exported names. `go/printer` prints them without bodies. Doc comments stay.                                                                 |
| Python     | A Python script. `ast` finds the public names and `__all__`. The script slices the source text by each node's `lineno` and `end_lineno`, so `#` comments stay, and replaces each body with `...`. |
| TypeScript | `ts.transpileDeclaration` (TypeScript 5.5 or newer) in the server makes a `.d.ts` per file. `typescript` is already a dependency.                                                                 |

Options we turned down:

- **Run codediff's Lua in headless Neovim.** Mission control must work
  without Neovim.
- **Port codediff's extractors to web-tree-sitter.** That would be about 1,700
  lines of Lua to port, and two copies of the same rules would drift apart. The
  language toolchains parse every piece of syntax, with far less code.

Mission control's API view will differ a little from codediff's, in
formatting and in some comment details. That is accepted: the two tools never
share a screen.

Known gap: a TypeScript function without a written return type shows no
return type, because no type checker runs. codediff shows only what is
written too, so nothing is lost compared with it.

## Parts

### 1. Read the sources

The API of a module needs every file of the module, at the base commit and at
the head commit. GitHub's patches hold only the changed lines.

- Keep a partial bare clone per repo, in `~/.cache/mission-control/repos/<repo>.git`,
  made with `git clone --bare --filter=blob:none`.
- For a pull request, `git fetch` the base commit and `pull/<n>/head`.
- List a directory with `git ls-tree <commit> -- <dir>/`, and read all its
  blobs in one `git cat-file --batch` call. codediff's `directory_sources`
  does the same.
- git gets the GitHub token through the environment, as
  `GIT_CONFIG_COUNT=1`, `GIT_CONFIG_KEY_0=http.extraHeader` and
  `GIT_CONFIG_VALUE_0`. The token never goes to disk or to a log.
- Cap the cache folder's size. Remove the clone that was used least recently
  first.

### 2. Group changed files into modules

Several changed files of one module give one API diff.

- **Go:** the package is the directory, without `_test.go` files.
- **Python:** the module is the file. If the directory's `__init__.py`
  re-exports from the file, the module is the package.
- **TypeScript:** the module is the file. If the directory's `index.ts` or
  `index.tsx` re-exports from the file, the module is the directory.
- A file in another language has no module. It keeps its line diff.

### 3. Extract the API

- Each helper takes JSON on stdin: a list of modules, each with its files as
  `{ path, text }`. It returns the API text for each module on stdout.
- Run one Go process and one Python process for each pull request, with every
  module in it. Never start a process per file.
- Build the Go program once, at server start, into the cache folder.
- Run the Python script with `python3 -I`, so it never imports code from the
  reviewed repo.
- The helpers live next to the server, for example `api/goapi/main.go` and
  `api/pyapi.py`. TypeScript runs in the server process.

### 4. Diff and cache

- Make a unified diff of each module's base and head API text, for example
  with `git diff --no-index`.
- Name the diff after the module, such as `internal/store (API)`, and pass it
  to the existing `toFileDiff` and `CodeView`.
- A new module shows its whole API as added. A removed module shows it as
  deleted.
- Cache the result by repo, base commit, head commit and module, like
  `filesCache` in `server.ts`.
- Serve it from a new endpoint, such as `/api/pr/<repo>/<n>/api`, so the line
  diff never waits for it.

### 5. Page

- A "Diff / API" switch in the review strip. The choice stays when the
  reviewer moves between files.
- In API mode, the file tree lists modules in place of their files. A file
  without an API view shows its line diff, as in codediff.
- While the clone fetches, the switch shows a loading state.

## Order of work

1. Sources and module grouping (parts 1 and 2), with Go only.
2. The Go helper, the diff, the cache and the endpoint (parts 3 and 4).
3. The switch on the page (part 5). The feature is usable from here, for Go.
4. The Python helper.
5. TypeScript.

## Tests

The extractors and the module grouping are parsing logic that can be wrong
while they still run cleanly. They qualify for tests under the repo rules.

- Golden files for each language: input sources and the expected API text.
- Module grouping, with git driven in a temp directory.
- The Go and Python helpers need their test commands in
  `just check-mission-control`.

## Open questions

- Should a line in the API diff link to its place in the line diff? Each
  helper can return a map from API line to source file and line, as codediff's
  `targets` does.
- Should the API view hide comments by default, as codediff's `C` key can?
