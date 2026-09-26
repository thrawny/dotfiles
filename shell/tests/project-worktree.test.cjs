const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const { spawnSync } = require('node:child_process');
const model = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../services/ProjectWorktree.js'), 'utf8'), model);

function fixture(t, remote = true) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'shell-worktree-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const repo = path.join(dir, 'project with spaces');
    const env = { ...process.env, HOME: dir, GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: '/dev/null', GIT_TERMINAL_PROMPT: '0' };
    function git(...args) {
        const result = spawnSync('git', args, { env, encoding: 'utf8' });
        assert.equal(result.status, 0, result.stderr);
        return result.stdout.trim();
    }
    git('init', '--initial-branch=trunk', repo);
    git('-C', repo, '-c', 'user.name=Test', '-c', 'user.email=test@example.com', '-c', 'commit.gpgsign=false', 'commit', '--allow-empty', '-m', 'initial');
    const origin = path.join(dir, 'origin.git');
    if (remote) {
        git('clone', '--bare', repo, origin);
        git('-C', repo, 'remote', 'add', 'origin', origin);
    }
    function run(branch, cwd = repo) {
        let state = model.begin(cwd, branch);
        for (let count = 0; state.command.length && count < 15; count++) {
            const result = spawnSync(state.command[0], Array.from(state.command).slice(1), { env, encoding: 'utf8' });
            state = model.advance(state, result.status, result.stdout, result.stderr);
        }
        assert.ok(['done', 'error'].includes(state.stage), `Workflow did not finish: ${state.stage}`);
        return state;
    }
    return { dir, repo, origin, git, run };
}

test('new branch fetches the remote default, not the current checkout branch', t => {
    const f = fixture(t);
    f.git('-C', f.repo, 'checkout', '-b', 'unrelated');
    f.git('-C', f.repo, '-c', 'user.name=Test', '-c', 'user.email=test@example.com', '-c', 'commit.gpgsign=false', 'commit', '--allow-empty', '-m', 'unrelated');
    const state = f.run('feature/nested');
    assert.equal(state.stage, 'done', state.error);
    assert.equal(state.path, f.repo + '-worktrees/feature/nested');
    assert.equal(state.workspace, 'project with spaces/feature/nested');
    assert.equal(f.git('-C', state.path, 'rev-parse', 'HEAD'), f.git('-C', f.repo, 'rev-parse', 'trunk'));
    assert.equal(f.git('-C', state.path, 'branch', '--show-current'), 'feature/nested');
    assert.equal(f.git('-C', state.path, 'for-each-ref', '--format=%(upstream)', 'refs/heads/feature/nested'), '');
});

test('an origin branch is fetched and tracked', t => {
    const f = fixture(t);
    f.git('--git-dir', f.origin, 'branch', 'review/123', 'trunk');
    const state = f.run('origin/review/123');
    assert.equal(state.stage, 'done', state.error);
    assert.equal(f.git('-C', state.path, 'rev-parse', '--abbrev-ref', '@{upstream}'), 'origin/review/123');
});

test('local branches work offline and an existing worktree is reused', t => {
    const f = fixture(t);
    f.git('-C', f.repo, 'branch', 'local');
    f.git('-C', f.repo, 'remote', 'set-url', 'origin', path.join(f.dir, 'missing'));
    const state = f.run('local');
    assert.equal(state.stage, 'done', state.error);
    assert.equal(f.run('local').path, state.path);
    assert.equal(f.run('local', state.path).path, state.path);
});

test('worktrees outside the naming convention are reused without moving them', t => {
    const f = fixture(t, false);
    const checkout = path.join(f.dir, 'custom checkout');
    f.git('-C', f.repo, 'worktree', 'add', '-b', 'existing', checkout);
    assert.equal(f.run('existing').path, checkout);
});

test('a project without origin creates from HEAD', t => {
    const f = fixture(t, false);
    assert.equal(f.run('offline').stage, 'done');
});

test('running from a linked worktree still uses the main project naming convention', t => {
    const f = fixture(t, false);
    const first = f.run('first');
    const second = f.run('second', first.path);
    assert.equal(second.path, f.repo + '-worktrees/second');
    assert.equal(second.stage, 'done', second.error);
});

test('network errors stop creation instead of falling back to another base', t => {
    const f = fixture(t);
    f.git('-C', f.repo, 'remote', 'set-url', 'origin', path.join(f.dir, 'missing'));
    const state = f.run('new-branch');
    assert.equal(state.stage, 'error');
    assert.ok(state.error);
    assert.equal(fs.existsSync(f.repo + '-worktrees/new-branch'), false);
});

test('an existing destination is not overwritten', t => {
    const f = fixture(t, false);
    const target = f.repo + '-worktrees/taken';
    fs.mkdirSync(target, { recursive: true });
    fs.writeFileSync(path.join(target, 'keep'), 'untouched');
    assert.equal(f.run('taken').stage, 'error');
    assert.equal(fs.readFileSync(path.join(target, 'keep'), 'utf8'), 'untouched');
});

test('invalid branch names cannot escape the worktree directory or become options', t => {
    const f = fixture(t, false);
    for (const name of ['', '-b', '../escape', '/absolute', 'a/../../escape', '@{-1}', 'with space'])
        assert.equal(f.run(name).stage, 'error', name);
});

test('fetch failure and missing remote HEAD are terminal errors', () => {
    const state = { cwd: '/repo', branch: 'topic', path: '/repo-worktrees/topic', stage: 'fetch' };
    assert.equal(model.advance(state, 128, '', 'fetch failed').error, 'fetch failed');
    assert.equal(model.advance({ ...state, stage: 'inspect' }, 0, '', '').stage, 'error');
});

test('porcelain parsing preserves spaces, newlines and detached checkouts', () => {
    const rows = model.rows('worktree /repo\0branch refs/heads/main\0\0worktree /a\nb\0detached\0\0');
    assert.equal(rows[0].branch, 'main');
    assert.equal(rows[1].path, '/a\nb');
    assert.equal(rows[1].branch, undefined);
});
