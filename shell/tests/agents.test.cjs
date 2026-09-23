const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const model = vm.createContext({});
vm.runInContext(fs.readFileSync('shell/services/AgentsModel.js', 'utf8'), model);
const base = {harness: 'pi', repo: 'fixture', branch: 'main', cold: false, parked: false, state_updated: 100, settled_at: null};
const threads = [
    {...base, seq: 1, order: 5, title: 'Old thread', area: 'work', lifecycle: 'active', attention: 'working'},
    {...base, seq: 2, order: 7, title: 'New thread', area: 'work', lifecycle: 'active', attention: 'approval'},
    {...base, seq: 3, order: 8, title: 'Other area', area: 'home', lifecycle: 'active', attention: 'input'},
    {...base, seq: 4, order: 9, title: 'Shelf', area: 'work', lifecycle: 'settled', attention: 'idle'},
    {...base, seq: 5, order: 10, title: 'Archive', area: 'work', lifecycle: 'archived', attention: 'idle'},
];
test('agents preserve user order and scope with separate shelves', () => {
    assert.deepEqual(Array.from(model.rows(threads, 'work', false, false, false), t => t.seq), [2, 1]);
    assert.deepEqual(Array.from(model.rows(threads, 'work', false, true, true), t => t.seq), [2, 1, 4, 5]);
    assert.deepEqual(Array.from(model.rows(threads, '', false, false, false), t => t.seq), [3, 2, 1]);
    assert.deepEqual(Array.from(model.rows(threads, 'work', true, false, false), t => t.seq), [3, 2, 1]);
    assert.equal(threads[0].seq, 1);
});
test('agent attention excludes settled and archived rows', () => {
    const counts = model.counts(threads);
    assert.equal(counts.active, 3);
    assert.equal(counts.approval, 1);
    assert.equal(counts.input, 1);
    assert.equal(counts.idle, 0);
    assert.equal(counts.archived, 1);
});
test('agent snapshots reject incompatible versions and invalid row identities', () => {
    const snapshot = {schema_version: 1, updated_at: 123, focused_area: 'work', threads};
    assert.equal(model.validate(snapshot), snapshot);
    assert.throws(() => model.validate({...snapshot, schema_version: 2}));
    assert.throws(() => model.validate({...snapshot, threads: [{...threads[0], seq: 'bad'}]}));
    assert.throws(() => model.validate({...snapshot, threads: [{...threads[0], attention: 'new-schema-state'}]}));
    assert.throws(() => model.validate({...snapshot, threads: [threads[0], threads[0]]}));
    for (const field of ['state_updated', 'harness', 'area', 'repo', 'branch', 'cold', 'settled_at'])
        assert.throws(() => model.validate({...snapshot, threads: [{...threads[0], [field]: undefined}]}));
});
test('agent duration tolerates clock changes', () => {
    assert.equal(model.age(200, 100), '0s');
    assert.equal(model.age(100, 159), '59s');
    assert.equal(model.age(100, 220), '2m');
    assert.equal(model.age(100, 7300), '2h');
});

const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
for (const scenario of ['invalid', 'version', 'missing', 'exit', 'timeout', 'action', 'late', 'rename', 'rename-gone']) {
    test(`agent service retains state and reports ${scenario} failure`, t => {
        const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'shell-agents-'));
        t.after(() => fs.rmSync(dir, {recursive: true, force: true}));
        fs.cpSync(path.resolve(__dirname, '../services'), path.join(dir, 'services'), {recursive: true});
        fs.cpSync(path.resolve(__dirname, '../modules/agents'), path.join(dir, 'modules/agents'), {recursive: true});
        fs.cpSync(path.resolve(__dirname, '../components'), path.join(dir, 'components'), {recursive: true});
        const config = path.join(dir, 'shell.qml');
        fs.writeFileSync(config, fs.readFileSync(path.join(__dirname, 'AgentsSmoke.qml'), 'utf8').replace('import "../services"', 'import "services"').replace('import "../modules/agents"', 'import "modules/agents"'));
        const fixture = path.join(dir, 'fixture.json');
        fs.writeFileSync(fixture, JSON.stringify({schema_version: 1, updated_at: Date.now() / 1000,
            focused_area: 'work', threads: [{...threads[1], title: 'Fixture thread'}]}));
        fs.writeFileSync(fixture + '.new', JSON.stringify({schema_version: 1, updated_at: Date.now() / 1000,
            focused_area: 'work', threads: [{...threads[1], title: 'Updated thread'}]}));
        const result = spawnSync('quickshell', ['-p', config], {
            env: {...process.env, QT_QPA_PLATFORM: 'offscreen', WAYLAND_DISPLAY: '', DISPLAY: '',
                XDG_RUNTIME_DIR: dir, XDG_CONFIG_HOME: dir, XDG_CACHE_HOME: dir,
                AGENTS_TEST_CASE: scenario, AGENTS_FIXTURE: fixture},
            encoding: 'utf8', timeout: 10000,
        });
        assert.equal(result.status, 0, `${result.error || ''}\n${result.stdout}\n${result.stderr}`);
        assert.ok(result.stdout.includes('Configuration Loaded'), result.stdout + result.stderr);
        assert.doesNotMatch(result.stdout + result.stderr, /ReferenceError|TypeError|Unable to assign|Binding loop/);
    });
}

test('agent shelves sort by most recent settlement rather than active ordering', () => {
    const shelf = [
        {...threads[3], seq: 10, order: 50, settled_at: 100},
        {...threads[3], seq: 11, order: 20, settled_at: 200},
        {...threads[4], seq: 12, order: 50, settled_at: 100},
        {...threads[4], seq: 13, order: 20, settled_at: 200},
    ];
    assert.deepEqual(Array.from(model.rows(shelf, '', true, true, true), t => t.seq), [11, 10, 13, 12]);
});
