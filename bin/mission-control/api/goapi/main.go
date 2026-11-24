// Command goapi prints what Go packages export, without function bodies.
//
// It reads a request as JSON on stdin: the Go files of a pull request's
// packages at its base and head commits, and the files the pull request
// changed. It writes one module per package directory to stdout, with the API
// text of each commit and the source line each API line came from.
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"go/ast"
	"go/doc"
	"go/parser"
	"go/printer"
	"go/token"
	"os"
	"path"
	"regexp"
	"slices"
	"sort"
	"strconv"
	"strings"
)

type request struct {
	// Comments keeps doc comments and field comments in the API text.
	Comments bool `json:"comments"`
	// Private adds unexported declarations, fields and methods.
	Private bool          `json:"private"`
	Changed []changedFile `json:"changed"`
	// Base and Head map a file's path to its text at that commit.
	Base map[string]string `json:"base"`
	Head map[string]string `json:"head"`
}

type changedFile struct {
	Path string `json:"path"`
	// PrevPath is the path at the base commit, when the file was renamed.
	PrevPath string `json:"prevPath"`
}

// A side is a package's API at one commit. Targets has one entry per line:
// an index into Sources and a line number there, or -1 and 0 for a line
// without a source, such as a blank one.
type side struct {
	Lines   []string `json:"lines"`
	Sources []string `json:"sources"`
	Targets [][2]int `json:"targets"`
}

// A module is one package directory. Base or Head is null when the directory
// has no Go files at that commit.
type module struct {
	ID    string   `json:"id"`
	Files []string `json:"files"`
	Base  *side    `json:"base"`
	Head  *side    `json:"head"`
}

type response struct {
	Modules []module `json:"modules"`
}

func main() {
	var req request
	if err := json.NewDecoder(os.Stdin).Decode(&req); err != nil {
		fmt.Fprintln(os.Stderr, "goapi:", err)
		os.Exit(1)
	}
	out := json.NewEncoder(os.Stdout)
	out.SetEscapeHTML(false)
	if err := out.Encode(response{Modules: modules(req)}); err != nil {
		fmt.Fprintln(os.Stderr, "goapi:", err)
		os.Exit(1)
	}
}

func inPackage(name string) bool {
	return strings.HasSuffix(name, ".go") && !strings.HasSuffix(name, "_test.go")
}

func modules(req request) []module {
	// Per package directory, the changed files it covers.
	covered := map[string][]string{}
	add := func(file, changed string) {
		if file == "" || !inPackage(file) {
			return
		}
		dir := path.Dir(file)
		if !slices.Contains(covered[dir], changed) {
			covered[dir] = append(covered[dir], changed)
		}
	}
	for _, f := range req.Changed {
		add(f.Path, f.Path)
		add(f.PrevPath, f.Path)
	}
	dirs := make([]string, 0, len(covered))
	for dir := range covered {
		dirs = append(dirs, dir)
	}
	sort.Strings(dirs)

	out := []module{}
	for _, dir := range dirs {
		base, baseName := extract(dir, req.Base, req)
		head, headName := extract(dir, req.Head, req)
		name := headName
		if head == nil {
			name = baseName
		}
		if name == "" {
			continue
		}
		sort.Strings(covered[dir])
		out = append(out, module{
			ID:    path.Join(dir, "package "+name),
			Files: covered[dir],
			Base:  base,
			Head:  head,
		})
	}
	return out
}

// The printer writes a //line directive wherever the source line of its
// output changes. Each file is parsed under a name no real directive uses.
const sourcePrefix = "mission-control-source-"

var directive = regexp.MustCompile(`^\s*//line ` + sourcePrefix + `(\d+)\.go:(\d+)$`)

// A block is one declaration's lines and their targets.
type block struct {
	lines   []string
	targets [][2]int
	// group is the same for declarations that read as one list, such as a
	// type's constructors and methods.
	group int
	fn    bool
}

type pkg struct {
	fset     *token.FileSet
	comments bool
	// sources holds each file's lines, to tell a blank line in the source from
	// one the printer left where it dropped an unexported field.
	sources [][]string
	blocks  []block
}

// extract returns the API of the package in dir, and the package's name. The
// side is nil when dir has no Go files.
func extract(dir string, files map[string]string, req request) (*side, string) {
	var paths []string
	for file := range files {
		if path.Dir(file) == dir && inPackage(file) {
			paths = append(paths, file)
		}
	}
	if len(paths) == 0 {
		return nil, ""
	}
	sort.Strings(paths)

	p := &pkg{fset: token.NewFileSet(), comments: req.Comments}
	parsed := make([]*ast.File, len(paths))
	count := map[string]int{}
	for i, file := range paths {
		text := files[file]
		p.sources = append(p.sources, strings.Split(text, "\n"))
		name := sourcePrefix + strconv.Itoa(i) + ".go"
		// A file with a syntax error still gives the declarations before it.
		f, _ := parser.ParseFile(p.fset, name, text, parser.ParseComments|parser.SkipObjectResolution)
		if f != nil && f.Name != nil {
			parsed[i] = f
			count[f.Name.Name]++
		}
	}
	// A directory can hold a stray file of another package, such as a
	// generator behind a build tag. The package most files name wins.
	name := ""
	for _, f := range parsed {
		if f != nil && count[f.Name.Name] > count[name] {
			name = f.Name.Name
		}
	}
	out := &side{Lines: []string{}, Sources: paths, Targets: [][2]int{}}
	if name == "" {
		return out, path.Base(dir)
	}
	var own []*ast.File
	for _, f := range parsed {
		if f != nil && f.Name.Name == name {
			own = append(own, f)
		}
	}
	first := own[0]
	clause := p.fset.Position(first.Package)

	// PreserveAST keeps each declaration's doc comment on it, for the printer.
	mode := doc.PreserveAST
	if req.Private {
		mode |= doc.AllDecls
	}
	docs, err := doc.NewFromFiles(p.fset, own, "", mode)
	if err != nil {
		return out, name
	}
	group := 0
	for _, v := range docs.Consts {
		p.add(v.Decl, group, false)
	}
	for _, v := range docs.Vars {
		p.add(v.Decl, group, false)
	}
	group++
	for _, f := range docs.Funcs {
		p.add(f.Decl, group, true)
	}
	for _, t := range docs.Types {
		group++
		p.add(t.Decl, group, false)
		for _, v := range t.Consts {
			p.add(v.Decl, group, false)
		}
		for _, v := range t.Vars {
			p.add(v.Decl, group, false)
		}
		for _, f := range t.Funcs {
			p.add(f.Decl, group, true)
		}
		for _, m := range t.Methods {
			p.add(m.Decl, group, true)
		}
	}
	if len(p.blocks) == 0 {
		return out, name
	}

	out.Lines = append(out.Lines, "package "+name)
	out.Targets = append(out.Targets, [2]int{p.source(clause.Filename), clause.Line})
	var prev *block
	for i := range p.blocks {
		b := &p.blocks[i]
		// Functions of one group read as a list. Everything else stands apart.
		listed := prev != nil && prev.fn && b.fn && prev.group == b.group &&
			len(prev.lines) == 1 && len(b.lines) == 1
		if !listed {
			out.Lines = append(out.Lines, "")
			out.Targets = append(out.Targets, [2]int{-1, 0})
		}
		out.Lines = append(out.Lines, b.lines...)
		out.Targets = append(out.Targets, b.targets...)
		prev = b
	}
	return out, name
}

func (p *pkg) source(filename string) int {
	text := strings.TrimSuffix(strings.TrimPrefix(filename, sourcePrefix), ".go")
	index, err := strconv.Atoi(text)
	if err != nil {
		return -1
	}
	return index
}

// add prints one declaration without its body, and records where each of its
// lines came from.
func (p *pkg) add(decl ast.Decl, group int, fn bool) {
	ast.Inspect(decl, func(n ast.Node) bool {
		switch n := n.(type) {
		case *ast.FuncDecl:
			n.Body = nil
			if !p.comments {
				n.Doc = nil
			}
		case *ast.GenDecl:
			if !p.comments {
				n.Doc = nil
			}
		case *ast.ValueSpec:
			if !p.comments {
				n.Doc, n.Comment = nil, nil
			}
		case *ast.TypeSpec:
			if !p.comments {
				n.Doc, n.Comment = nil, nil
			}
		case *ast.Field:
			if !p.comments {
				n.Doc, n.Comment = nil, nil
			}
		// go/doc marks a type it removed unexported members from, and the
		// printer then writes a comment that says so. An unexported member is
		// no part of the API, so the mark goes.
		case *ast.StructType:
			n.Incomplete = false
		case *ast.InterfaceType:
			n.Incomplete = false
		}
		return true
	})

	// The text comes from a plain print. A second print with //line
	// directives tells where each line came from. The directives upset the
	// printer's indentation, so that print gives no text.
	plain, ok := p.print(decl, 0)
	traced, _ := p.print(decl, printer.SourcePos)
	if !ok {
		return
	}
	var targets [][2]int
	file, line := -1, 0
	for _, text := range traced {
		if m := directive.FindStringSubmatch(text); m != nil {
			file, _ = strconv.Atoi(m[1])
			line, _ = strconv.Atoi(m[2])
			continue
		}
		target := [2]int{-1, 0}
		if file >= 0 {
			target = [2]int{file, line}
			line++
		}
		targets = append(targets, target)
	}
	exact := len(targets) == len(plain)
	if !exact {
		// The two prints disagree, so every line points at the declaration.
		pos := p.fset.Position(decl.Pos())
		targets = make([][2]int, len(plain))
		for i := range targets {
			targets[i] = [2]int{p.source(pos.Filename), pos.Line}
		}
	}
	b := block{group: group, fn: fn}
	for i, text := range plain {
		target := targets[i]
		if strings.TrimSpace(text) == "" {
			// The printer leaves a blank line where it dropped an unexported
			// field. A blank line stays only where the source has one.
			if !exact || i == 0 || i+1 == len(plain) || !p.blankBetween(targets[i-1], targets[i+1]) {
				continue
			}
			target = [2]int{-1, 0}
		}
		b.lines = append(b.lines, text)
		b.targets = append(b.targets, target)
	}
	if len(b.lines) > 0 {
		p.blocks = append(p.blocks, b)
	}
}

func (p *pkg) print(decl ast.Decl, mode printer.Mode) ([]string, bool) {
	var buf bytes.Buffer
	config := printer.Config{Mode: printer.UseSpaces | printer.TabIndent | mode, Tabwidth: 8}
	if err := config.Fprint(&buf, p.fset, decl); err != nil {
		return nil, false
	}
	return strings.Split(strings.TrimRight(buf.String(), "\n"), "\n"), true
}

// blankBetween reports whether the source has a blank line between two
// lines of one file.
func (p *pkg) blankBetween(above, below [2]int) bool {
	if above[0] != below[0] || above[0] < 0 || above[0] >= len(p.sources) {
		return false
	}
	lines := p.sources[above[0]]
	for line := above[1] + 1; line < below[1] && line <= len(lines); line++ {
		if strings.TrimSpace(lines[line-1]) == "" {
			return true
		}
	}
	return false
}
