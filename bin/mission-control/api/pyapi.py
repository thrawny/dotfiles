#!/usr/bin/env python3
"""Print what Python modules export, like stub files.

Reads a request as JSON on stdin: the Python files of a pull request's modules
at its base and head commits, and the files the pull request changed. Writes
one module per changed file or package to stdout, with the API text of each
commit and the source line each API line came from.

A function shows its signature and decorators, with `...` for its body. A
class shows its public attributes, methods and nested classes. Assignments
show as written. A name is public if the module's `__all__` lists it, or,
without `__all__`, if it has no leading underscore.

A module is one file. A file that its directory's `__init__.py` re-exports
from belongs to the package instead: the API of `__init__.py`, with each
re-exporting import followed by the definitions it brings in.

The rules follow codediff.nvim's API view (lua/codediff/api/python.lua). Run
it with `python3 -I`, so it never imports code from the reviewed repository.
"""

from __future__ import annotations

import ast
import bisect
import io
import json
import posixpath
import sys
import tokenize
from collections.abc import Callable
from dataclasses import dataclass
from typing import Any, TypeGuard

Shown = Callable[[str], bool]
Definition = ast.FunctionDef | ast.AsyncFunctionDef | ast.ClassDef


@dataclass
class Line:
    text: str
    file: str | None = None
    # The 0-based source row, or None for a line the view adds.
    row: int | None = None


@dataclass(eq=False)
class Module:
    path: str
    text: str
    lines: list[str]
    tree: ast.Module
    # Per 0-based row, the column its comment starts at.
    comment_col: dict[int, int]
    # The position of every `:` operator, in source order.
    colons: list[tuple[int, int]]
    # The names in __all__, or None without one.
    exported: set[str] | None


@dataclass(eq=False)
class Entry:
    """One statement's lines, and the source rows it spans."""

    lines: list[Line]
    module: Module | None = None
    first: int = 0
    last: int = 0
    # A group always stands apart from its neighbours.
    group: bool = False


class Extractor:
    def __init__(self, comments: bool) -> None:
        # Whether the view keeps comments and docstrings.
        self.comments = comments

    def copy(
        self, module: Module, first: int, last: int, last_col: int | None = None
    ) -> list[Line]:
        """Source rows first to last as view lines, the last cut at last_col.

        With comments hidden, comments are cut out, and lines that leaves
        blank are dropped.
        """
        out: list[Line] = []
        for row in range(first, last + 1):
            line = module.lines[row] if row < len(module.lines) else ""
            if row == last and last_col is not None:
                line = line[:last_col]
            col = None if self.comments else module.comment_col.get(row)
            if col is not None and col < len(line):
                line = line[:col].rstrip()
                if not line.strip():
                    continue
            out.append(Line(line, module.path, row))
        return out

    def leading_comments(self, module: Module, node: ast.stmt) -> list[Line]:
        """The run of comments right above a statement, at its column."""
        if not self.comments:
            return []
        row = first_row(node)
        line = module.lines[row]
        col = len(line) - len(line.lstrip())
        first = row
        while first > 0 and module.comment_col.get(first - 1) == col:
            if module.lines[first - 1][:col].strip():
                break
            first -= 1
        return self.copy(module, first, row - 1)

    def header(self, module: Module, node: Definition) -> tuple[list[Line], bool]:
        """A def's or class's lines up to its colon, decorators included.

        Its docstring follows if comments show. Returns the lines, and
        whether a docstring is in them.
        """
        body = node.body[0]
        start = first_row(body), char_col(module, body)
        if isinstance(body, Definition) and body.decorator_list:
            # The first decorator's @ is one column before its expression.
            decorator = body.decorator_list[0]
            start = first_row(body), char_col(module, decorator) - 1
        # Between the header's colon and the body are only comments and
        # blank lines, so the colon is the last one before the body.
        index = bisect.bisect_left(module.colons, start) - 1
        own = (node.lineno - 1, 0)
        if index >= 0 and module.colons[index] >= own:
            row, col = module.colons[index]
        else:
            row, col = node.lineno - 1, len(module.lines[node.lineno - 1]) - 1
        lines = self.copy(module, first_row(node), row, col + 1)
        if not (self.comments and is_string(body)):
            return lines, False
        end = (body.end_lineno or body.lineno) - 1
        if body.lineno - 1 > row:
            lines += self.copy(module, body.lineno - 1, end)
        else:
            # A docstring on the def's own line.
            lines[-1].text += " " + (ast.get_source_segment(module.text, body) or "")
        return lines, True

    def entry(
        self,
        module: Module,
        node: ast.stmt,
        shown: Shown,
        after: ast.stmt | None = None,
    ) -> Entry | None:
        """The entry for one statement, or None if it defines no shown name.

        after is the statement below it, which can be its docstring.
        """
        if not any(shown(name) for name in names_of(node)):
            return None
        lines = self.leading_comments(module, node)
        last = (node.end_lineno or node.lineno) - 1
        if isinstance(node, Definition):
            head, documented = self.header(module, node)
            body = self.members(module, node) if isinstance(node, ast.ClassDef) else []
            if not documented and not body:
                head[-1].text += " ..."
            lines += head
            # The first member follows the header, or the docstring as in
            # the source.
            previous = Entry([], module, last=head[-1].row or 0) if documented else None
            join(body, lines, previous)
        else:
            lines += self.copy(module, node.lineno - 1, last)
            # An attribute docstring: a string right below an assignment.
            if self.comments and is_string(after) and after.lineno - 1 == last + 1:
                lines += self.copy(
                    module, after.lineno - 1, (after.end_lineno or after.lineno) - 1
                )
        return Entry(lines, module, lines[0].row or 0, last)

    def members(self, module: Module, node: ast.ClassDef) -> list[Entry]:
        return self.entries(module, node.body, public)

    def entries(
        self, module: Module, body: list[ast.stmt], shown: Shown
    ) -> list[Entry]:
        out: list[Entry] = []
        for index, node in enumerate(body):
            after = body[index + 1] if index + 1 < len(body) else None
            if isinstance(node, (ast.Import, ast.ImportFrom)):
                found = self.import_entry(module, node)
            else:
                found = self.entry(module, node, shown, after)
            if found:
                out.append(found)
        return out

    def import_entry(
        self, module: Module, node: ast.Import | ast.ImportFrom
    ) -> Entry | None:
        """An import's entry if it binds a name in the module's __all__."""
        if not module.exported:
            return None
        if not any(bound in module.exported for bound, _ in import_names(node)):
            return None
        last = (node.end_lineno or node.lineno) - 1
        return Entry(
            self.copy(module, node.lineno - 1, last), module, node.lineno - 1, last
        )

    def module_entries(self, module: Module) -> list[Entry]:
        """The entries of a module's own top-level statements."""
        return self.entries(module, module.tree.body, module_shown(module))

    def resolve(
        self,
        load: Callable[[str], Module | None],
        modname: str,
        name: str,
        visited: set[str],
    ) -> list[Entry]:
        """The definitions of name in a module of the package.

        Follows the module's own imports from other modules of the package.
        """
        module = load(modname)
        if not module or modname in visited:
            return []
        visited.add(modname)
        found = self.entries(
            module,
            [
                n
                for n in module.tree.body
                if not isinstance(n, ast.Import | ast.ImportFrom)
            ],
            lambda candidate: candidate == name,
        )
        if found:
            return found
        for node in module.tree.body:
            sibling = sibling_module(module, node)
            if sibling and isinstance(node, ast.ImportFrom):
                for bound, original in import_names(node):
                    if bound == name:
                        return self.resolve(load, sibling, original, visited)
        return []

    def package_entries(
        self, init: Module, load: Callable[[str], Module | None]
    ) -> list[Entry]:
        """The package's API, from its __init__.py.

        Its own entries, and each import from another module of the package
        followed by the definitions it re-exports.
        """
        shown = module_shown(init)
        out: list[Entry] = []
        body = init.tree.body
        for index, node in enumerate(body):
            sibling = sibling_module(init, node)
            if sibling and isinstance(node, ast.ImportFrom):
                definitions: list[Entry] = []
                if any(alias.name == "*" for alias in node.names):
                    target = load(sibling)
                    definitions = self.module_entries(target) if target else []
                else:
                    for bound, original in import_names(node):
                        if shown(bound):
                            definitions += self.resolve(load, sibling, original, set())
                if definitions:
                    last = (node.end_lineno or node.lineno) - 1
                    lines = self.copy(init, node.lineno - 1, last)
                    out.append(Entry(join(definitions, lines), group=True))
                    continue
            if isinstance(node, (ast.Import, ast.ImportFrom)):
                # A re-export from outside the package shows as its import.
                found = self.import_entry(init, node)
            else:
                after = body[index + 1] if index + 1 < len(body) else None
                found = self.entry(init, node, shown, after)
            if found:
                out.append(found)
        return out

    def view(self, sources: dict[str, str], path: str, package: bool) -> list[Line]:
        """The API of the file at path, or of the package it is the
        __init__.py of."""
        module = parse(path, sources[path])
        if package:
            parsed: dict[str, Module | None] = {}

            def load(modname: str) -> Module | None:
                if modname not in parsed:
                    sibling = posixpath.join(posixpath.dirname(path), modname + ".py")
                    parsed[modname] = None
                    if sibling in sources and sibling != path:
                        try:
                            parsed[modname] = parse(sibling, sources[sibling])
                        except SyntaxError:
                            pass
                return parsed[modname]

            entries = self.package_entries(module, load)
        else:
            entries = self.module_entries(module)
        if not entries:
            return []
        first = module.tree.body[0] if module.tree.body else None
        if self.comments and first and is_string(first):
            doc = self.copy(
                module, first.lineno - 1, (first.end_lineno or first.lineno) - 1
            )
            entries.insert(0, Entry(doc, group=True))
        return join(entries)


def first_row(node: ast.stmt) -> int:
    """The 0-based row a statement starts on, decorators included."""
    rows = [node.lineno]
    if isinstance(node, Definition):
        rows += [decorator.lineno for decorator in node.decorator_list]
    return min(rows) - 1


def char_col(module: Module, node: ast.AST) -> int:
    """A node's column in characters. ast counts UTF-8 bytes."""
    line = module.lines[getattr(node, "lineno") - 1]
    return len(line.encode()[: getattr(node, "col_offset")].decode(errors="replace"))


def is_string(node: ast.stmt | None) -> TypeGuard[ast.Expr]:
    return (
        isinstance(node, ast.Expr)
        and isinstance(node.value, ast.Constant)
        and isinstance(node.value.value, str)
    )


def public(name: str) -> bool:
    """A public name: no leading underscore, or a dunder such as __init__."""
    return not name.startswith("_") or (
        name.startswith("__") and name.endswith("__") and len(name) > 4
    )


def names_of(node: ast.stmt) -> list[str]:
    """The names a top-level or class-level statement defines."""
    if isinstance(node, Definition):
        return [node.name]
    alias = getattr(ast, "TypeAlias", None)
    if alias is not None and isinstance(node, alias):
        return [getattr(node, "name").id]
    targets: list[ast.expr] = []
    if isinstance(node, ast.Assign):
        targets = node.targets
    elif isinstance(node, ast.AnnAssign):
        targets = [node.target]
    names: list[str] = []
    for target in targets:
        if isinstance(target, ast.Name):
            names.append(target.id)
        elif isinstance(target, (ast.Tuple, ast.List)):
            names += [item.id for item in target.elts if isinstance(item, ast.Name)]
    return names


def import_names(node: ast.Import | ast.ImportFrom) -> list[tuple[str, str]]:
    """Per imported name: the name it binds, and its name in its module."""
    if isinstance(node, ast.ImportFrom):
        return [(alias.asname or alias.name, alias.name) for alias in node.names]
    # `import a.b` binds a.
    return [
        (alias.asname or alias.name.split(".")[0], alias.name) for alias in node.names
    ]


def sibling_module(module: Module, node: ast.stmt) -> str | None:
    """The module of the same package an import brings names from.

    This is server in `from .server import X`, and in
    `from shop.server import X` or `from app.shop.server import X` within
    the package shop.
    """
    if not isinstance(node, ast.ImportFrom) or not node.module:
        return None
    parts = node.module.split(".")
    if node.level == 1 and len(parts) == 1:
        return parts[0]
    package = posixpath.basename(posixpath.dirname(module.path))
    if node.level == 0 and len(parts) >= 2 and parts[-2] == package:
        return parts[-1]
    return None


def module_shown(module: Module) -> Shown:
    """Whether a top-level name is in a module's API.

    A name is in it if __all__ lists it, or, without __all__, if it is
    public. __all__ itself is not.
    """

    def shown(name: str) -> bool:
        if name == "__all__":
            return False
        if module.exported is not None:
            return name in module.exported
        return public(name)

    return shown


def exported_names(tree: ast.Module) -> set[str] | None:
    names: set[str] | None = None
    for node in tree.body:
        target: ast.expr | None = None
        if isinstance(node, ast.Assign) and len(node.targets) == 1:
            target = node.targets[0]
        elif isinstance(node, (ast.AugAssign, ast.AnnAssign)):
            target = node.target
        value = getattr(node, "value", None)
        if not (isinstance(target, ast.Name) and target.id == "__all__"):
            continue
        names = names or set()
        if isinstance(value, (ast.List, ast.Tuple)):
            for item in value.elts:
                if isinstance(item, ast.Constant) and isinstance(item.value, str):
                    names.add(item.value)
    return names


def parse(path: str, text: str) -> Module:
    tree = ast.parse(text)
    comment_col: dict[int, int] = {}
    colons: list[tuple[int, int]] = []
    try:
        for token in tokenize.generate_tokens(io.StringIO(text).readline):
            if token.type == tokenize.COMMENT:
                comment_col[token.start[0] - 1] = token.start[1]
            elif token.type == tokenize.OP and token.string == ":":
                colons.append((token.start[0] - 1, token.start[1]))
    except (tokenize.TokenError, SyntaxError):
        pass
    return Module(
        path, text, text.split("\n"), tree, comment_col, colons, exported_names(tree)
    )


def apart(above: Entry, below: Entry) -> bool:
    """Whether two entries in a row are apart in the source.

    A blank line between them counts, such as between two methods. Groups,
    entries from different files and entries out of source order are always
    apart.
    """
    if above.group or below.group or above.module is not below.module:
        return True
    if below.first <= above.last or above.module is None:
        return True
    lines = above.module.lines
    return any(not lines[row].strip() for row in range(above.last + 1, below.first))


def join(
    entries: list[Entry], out: list[Line] | None = None, previous: Entry | None = None
) -> list[Line]:
    """Join entries into view lines, after out's lines if given.

    A blank line goes between two entries that are apart in the source.
    """
    lines = out if out is not None else []
    for entry in entries:
        if previous and apart(previous, entry):
            lines.append(Line(""))
        lines += entry.lines
        previous = entry
    return lines


def side(lines: list[Line]) -> dict[str, Any]:
    sources = sorted({line.file for line in lines if line.file})
    index = {path: number for number, path in enumerate(sources)}
    return {
        "lines": [line.text for line in lines],
        "sources": sources,
        "targets": [
            [index[line.file], line.row + 1]
            if line.file and line.row is not None
            else [-1, 0]
            for line in lines
        ],
    }


def modules(request: dict[str, Any]) -> list[dict[str, Any]]:
    extractor = Extractor(bool(request.get("comments")))
    # Which files a package's API comes from never depends on comments.
    plain = Extractor(False)
    sides: dict[str, dict[str, str]] = {
        "base": request["base"],
        "head": request["head"],
    }

    def init_of(path: str) -> str:
        return posixpath.join(posixpath.dirname(path), "__init__.py")

    def in_package(sources: dict[str, str], path: str) -> bool:
        """Whether the package's API shows anything from the file at path."""
        init = init_of(path)
        if init not in sources:
            return False
        if init == path:
            return True
        try:
            return any(line.file == path for line in plain.view(sources, init, True))
        except SyntaxError:
            return False

    # Per module id, the changed files it covers and the paths to show.
    found: dict[str, dict[str, Any]] = {}
    for changed in request["changed"]:
        head_path: str = changed["path"]
        base_path: str = changed.get("prevPath") or head_path
        # The head commit decides the module. A deleted file goes by the
        # base commit.
        if head_path in sides["head"]:
            grouped = in_package(sides["head"], head_path)
        elif base_path in sides["base"]:
            grouped = in_package(sides["base"], base_path)
        else:
            continue
        if grouped:
            key = init_of(head_path)
            module = found.setdefault(
                key, {"files": [], "package": True, "base": key, "head": key}
            )
        else:
            module = found.setdefault(
                head_path,
                {"files": [], "package": False, "base": base_path, "head": head_path},
            )
        module["files"].append(head_path)

    out: list[dict[str, Any]] = []
    for key in sorted(found):
        module = found[key]
        result: dict[str, Any] = {"id": key, "files": sorted(module["files"])}
        try:
            for name, sources in sides.items():
                path = module[name]
                result[name] = (
                    side(extractor.view(sources, path, module["package"]))
                    if path in sources
                    else None
                )
        except SyntaxError:
            # A file this Python cannot parse keeps its line diff.
            continue
        out.append(result)
    return out


def main() -> None:
    request = json.load(sys.stdin)
    json.dump({"modules": modules(request)}, sys.stdout, ensure_ascii=False)


if __name__ == "__main__":
    main()
