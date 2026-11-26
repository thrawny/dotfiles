# The API view on the review page

Status: built, for Go, Python and TypeScript. This file records how it works,
and where it left the first plan.

## Goal

The review page has a second way to read a pull request. Besides the line
diff, it shows a diff of what each changed module exports, without function
bodies. A reviewer then sees first how a change affects other code, and reads
the bodies second.

The model is the API state in [codediff.nvim](https://github.com/thrawny/codediff.nvim)
(`lua/codediff/api/`), which does this in Neovim for Go, Python and
TypeScript. Mission control works on its own: it never calls Neovim.

## On the page

- A "Diff / API" switch in the review strip, and the `a` key. The choice is
  saved, so it holds for every pull request.
- The number on the switch counts the modules whose API changed. A pull
  request that changes bodies only shows 0.
- In the API view, each module stands in for the changed files it covers.
  The file tree lists the modules first in each folder, and marks the ones
  whose API changed.
- A module whose API did not change starts collapsed and says so. A new
  module shows its API as plain text, as the page shows a new file.
- A file without an API view keeps its line diff: a file in another
  language, a test, or a file of a module that exports nothing.
- Comments are hidden at first. The "Comments" switch and the `C` key show
  them. Docstrings count as comments.
- A click on a line number opens the line's source. It scrolls to the line in
  the line diff when the diff shows that line. For a line outside every hunk,
  such as an unchanged declaration, it opens the file on GitHub at that
  commit and line.
- The lines between the hunks of an API diff can open, because the page has
  the whole text of both sides.
- Unexported declarations are hidden at first too. The "Unexported" switch
  and the `P` key show them: unexported Go names, fields and methods, Python
  names with a leading underscore or outside `__all__`, and TypeScript
  declarations without `export` and private class members. A module that
  exports nothing then has an API view.
- The keys are codediff's: `a` and `s` switch the view, `C` shows comments
  and `P` shows unexported declarations. Approving has no key.
- The API view loads beside the pull request, so the switch finds it ready.

## Extraction

Each language reads its own API with its own toolchain. Mission control
needs `go` and `python3` on its `PATH`.

| Language   | Tool                                                                                                                                                                                            |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Go         | `api/goapi/main.go`. `go/doc` finds what a package exports and sorts it, with each type's constructors and methods below it. `go/printer` prints each declaration without its body.             |
| Python     | `api/pyapi.py`. `ast` finds the public names and `__all__`. The script copies the source lines of each signature, so the text reads as written, with `...` for a body.                          |
| TypeScript | `api/typescript.ts`. `ts.transpileDeclaration` makes a declaration file from one source file, in the server process. It needs TypeScript 5, installed as `typescript5` beside the type checker. |

The three take the same request and give the same answer, described in
`api/languages.ts`. The request holds the two settings, the changed
files, and every file read at each commit. The answer is a list of modules.
Each has the API text of both commits and, for each line, the source file and
line it came from.

- **Go** prints each declaration twice: once for the text, and once with
  `//line` directives to learn where each line came from. The directives
  upset the printer's indentation, so the second print gives no text.
- **Python** runs with `python3 -I`, so it never imports code from the
  reviewed repository. A file it cannot parse keeps its line diff.
- **TypeScript** runs no type check. A type the file does not spell out comes
  out as `any` or `unknown`, and the compiler reports where. The extractor
  removes that type from a return type, a variable and a class property. It
  stays in an object literal's members. Private class members are left out.
  The compiler writes only what a file exports, so to show the rest the
  extractor exports every declaration first and takes the word off again.
  A private member shows its name without a type.

Options we turned down:

- **Run codediff's Lua in headless Neovim.** Mission control must work
  without Neovim.
- **Port codediff's extractors to web-tree-sitter.** That would be about 1,700
  lines of Lua to port, and two copies of the same rules would drift apart.

The API text differs a little from codediff's, in formatting and in order.
That is accepted: the two tools never share a screen.

## Modules

- **Go:** the package is the directory, without `_test.go` files. Its tree
  entry is named `package store`.
- **Python:** the module is the file. If the directory's `__init__.py`
  re-exports from the file, the module is the package: the API of
  `__init__.py`, with each re-exporting import followed by the definitions
  it brings in.
- **TypeScript:** the same, with `index.ts` or `index.tsx`.
- The head commit decides which module a file belongs to. A deleted file
  goes by the base commit.
- A test is no part of a module's API. `api/languages.ts` holds the path
  rules.

## Sources

The API of a module needs every file of the module, at both commits.
GitHub's patches hold only the changed lines. `api/sources.ts` reads the
files with git.

- The base commit is the merge base of the base branch and the head, from
  GitHub's compare API. The tip of the base branch would show other people's
  changes as the pull request's.
- Each repository has a bare repository in
  `~/.cache/mission-control/repos/<repo>.git`. It starts empty. No clone
  runs.
- One fetch at depth 1 with `--filter=blob:none` brings both commits and
  their trees. One more fetch brings the blobs that are missing, for both
  commits at once.
- `git ls-tree` lists the directories, and one `git cat-file --batch` call
  reads the blobs.
- git gets the GitHub token as an `http.extraHeader` setting through the
  environment. The token never goes to disk or to a log.
- Credential helpers are off. One that asks, such as the macOS keychain,
  would leave a refused fetch waiting.
- The repositories together stay under 2 GiB. The one used longest ago goes
  first.

Measured on three public repositories: reading the sources and extracting
the API took 1.3 to 2.4 seconds the first time, and 0.1 to 0.3 seconds once
the blobs were there.

## Server

- `GET /api/pr/<repo>/<n>/api` answers with the modules. `?comments` asks for
  the text with comments, and `?private` for unexported declarations.
- The answer is cached by repository, base branch tip, head commit and
  the two settings.
- The Go helper is built once into `~/.cache/mission-control/bin`, under a
  name that carries a hash of its source.
- A language that fails, such as Go without a toolchain, is named in the
  answer. Its files keep their line diffs, and the strip says which language
  failed.
- `mission-control run` installs the locked packages before it starts.
  bun's fallback install cannot find a package under a second name.

## Tests

`api/view.test.ts` runs in `just check-mission-control`.

- A case file per language in `api/testdata` holds the sources of both
  commits. Its expected API text is beside it, for comments hidden and
  shown and for unexported declarations shown. `UPDATE_GOLDEN=1 bun test` writes the expected text again.
- One test builds a git repository in a temp directory and reads a pull
  request's modules from it by fetch, as from GitHub.

## Not built

- Opening the lines between the hunks of a line diff. The viewer can load
  whole files for that through its `loadDiffFiles` option, and
  `api/sources.ts` can read them. A click on an API line could then always
  stay on the page.
