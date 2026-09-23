const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const adapter = path.resolve(__dirname, '../../bin/shell-clipboard-image');
const realCliphist = spawnSync('which', ['cliphist'], { encoding: 'utf8' }).stdout.trim();

function fixture(t) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'shell-image-qml-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const env = {
        ...process.env,
        QT_QPA_PLATFORM: 'offscreen', WAYLAND_DISPLAY: '', DISPLAY: '',
        XDG_RUNTIME_DIR: dir, XDG_CONFIG_HOME: dir, XDG_CACHE_HOME: dir,
        CLIPHIST_DB_PATH: path.join(dir, 'db'),
        IMAGE_CAPTURE_FILE: path.join(dir, 'copied'),
        IMAGE_DECODE_MARKER: path.join(dir, 'decode-started'),
        IMAGE_REAL_CLIPHIST: realCliphist,
    };
    for (const ext of ['png', 'gif']) {
        const stored = spawnSync(realCliphist, ['-db-path', env.CLIPHIST_DB_PATH, 'store'], {
            env, input: fs.readFileSync(path.join(__dirname, `fixtures/clipboard.${ext}`)),
        });
        assert.equal(stored.status, 0, stored.stderr.toString());
    }
    fs.mkdirSync(path.join(dir, 'tools'));
    fs.symlinkSync(adapter, path.join(dir, 'tools/shell-clipboard-image'));
    const fakeTool = path.join(dir, 'tools/fake-tool');
    fs.writeFileSync(fakeTool, `#!/usr/bin/env python3
import os, pathlib, sys, time
if pathlib.Path(sys.argv[0]).name == 'cliphist':
    if sys.argv[-1] == 'decode':
        pathlib.Path(os.environ['IMAGE_DECODE_MARKER']).touch()
        if os.environ.get('IMAGE_OVERSIZE'):
            os.lseek(1, 64 * 1024 * 1024 - 1, os.SEEK_SET)
            os.write(1, b'x')
            os.write(1, b'x')
        time.sleep(float(os.environ.get('IMAGE_DECODE_DELAY', '0')))
    os.execv(os.environ['IMAGE_REAL_CLIPHIST'], [os.environ['IMAGE_REAL_CLIPHIST'], *sys.argv[1:]])
else:
    if os.environ.get('IMAGE_COPY_FAILURE'):
        sys.exit(1)
    pathlib.Path(os.environ['IMAGE_CAPTURE_FILE']).write_bytes(sys.stdin.buffer.read())
`, { mode: 0o700 });
    fs.symlinkSync(fakeTool, path.join(dir, 'tools/cliphist'));
    fs.symlinkSync(fakeTool, path.join(dir, 'tools/wl-copy'));
    env.PATH = path.join(dir, 'tools') + path.delimiter + process.env.PATH;
    return { dir, env };
}

function request(env, data) {
    return spawnSync(adapter, ['--db-path', env.CLIPHIST_DB_PATH], {
        env, input: JSON.stringify(data), encoding: 'utf8', timeout: 10000,
    });
}

for (const scenario of ['preview', 'copy', 'cancel', 'replace']) {
    test(`image QML integration: ${scenario}`, t => {
        const { dir, env } = fixture(t);
        env.CLIPBOARD_TEST_CASE = scenario;
        if (['cancel', 'replace'].includes(scenario)) env.IMAGE_DECODE_DELAY = '0.45';
        fs.mkdirSync(path.join(dir, 'services'));
        for (const name of ['Clipboard.qml', 'Search.js'])
            fs.copyFileSync(path.resolve(__dirname, '../services', name), path.join(dir, 'services', name));
        fs.writeFileSync(path.join(dir, 'services/qmldir'), 'singleton Clipboard 1.0 Clipboard.qml\n');
        const config = path.join(dir, 'shell.qml');
        fs.writeFileSync(config, fs.readFileSync(path.join(__dirname, 'ClipboardImages.qml'), 'utf8').replace('import "../services"', 'import "services"'));
        const result = spawnSync('quickshell', ['-p', config], { env, encoding: 'utf8', timeout: 10000 });
        assert.equal(result.status, 0, `${result.error || ''}\n${result.stdout}\n${result.stderr}`);
        assert.ok(result.stdout.includes('Configuration Loaded'));
        assert.ok(fs.existsSync(env.IMAGE_DECODE_MARKER));
        assert.deepEqual(fs.readdirSync(path.join(dir, 'dotfiles-clipboard')), [], 'closing must remove image files');
        if (scenario === 'copy')
            assert.deepEqual(fs.readFileSync(env.IMAGE_CAPTURE_FILE), fs.readFileSync(path.join(__dirname, 'fixtures/clipboard.png')));
        else
            assert.equal(fs.existsSync(env.IMAGE_CAPTURE_FILE), false, 'preview or cancelled selection must never call wl-copy');
    });
}

test('image adapter validates stdin IDs and removes abandoned private sessions', t => {
    const { dir, env } = fixture(t);
    const invalid = request(env, { operation: 'prepare', session: 'safe', id: '../1' });
    assert.notEqual(invalid.status, 0);
    const prepared = request(env, { operation: 'prepare', session: 'first', id: '1' });
    assert.equal(prepared.status, 0, prepared.stderr);
    const data = JSON.parse(prepared.stdout);
    assert.deepEqual(fs.readFileSync(data.path), fs.readFileSync(path.join(__dirname, 'fixtures/clipboard.png')));
    assert.equal(fs.statSync(path.dirname(data.path)).mode & 0o777, 0o700);
    assert.equal(fs.statSync(data.path).mode & 0o777, 0o600);
    const next = request(env, { operation: 'prepare', session: 'replacement', id: '2' });
    assert.equal(next.status, 0, next.stderr);
    assert.equal(fs.existsSync(path.join(dir, 'dotfiles-clipboard/first')), false, 'a new picker removes abandoned session of the same owner');
    const cleanup = request(env, { operation: 'cleanup', session: 'replacement' });
    assert.equal(cleanup.status, 0, cleanup.stderr);
    assert.deepEqual(fs.readdirSync(path.join(dir, 'dotfiles-clipboard')), []);
});

test('image adapter bounds temporary output and reports failed copies without exposing data', t => {
    const { dir, env } = fixture(t);
    const oversized = request({ ...env, IMAGE_OVERSIZE: '1' }, { operation: 'prepare', session: 'bounded', id: '1' });
    assert.notEqual(oversized.status, 0);
    assert.deepEqual(JSON.parse(oversized.stdout), { error: 'image-too-large' });
    assert.deepEqual(fs.readdirSync(path.join(dir, 'dotfiles-clipboard/bounded')), ['.owner']);
    const prepared = request(env, { operation: 'prepare', session: 'bounded', id: '1' });
    assert.equal(prepared.status, 0, prepared.stderr);
    const failed = request({ ...env, IMAGE_COPY_FAILURE: '1' }, { operation: 'copy', session: 'bounded', id: '1' });
    assert.notEqual(failed.status, 0);
    assert.equal(failed.stdout, '');
    assert.equal(fs.existsSync(env.IMAGE_CAPTURE_FILE), false);
});

test('image adapter evicts older originals when the session reaches its image limit', t => {
    const { env } = fixture(t);
    const prepared = request(env, { operation: 'prepare', session: 'bounded', id: '1' });
    assert.equal(prepared.status, 0, prepared.stderr);
    const directory = path.dirname(JSON.parse(prepared.stdout).path);
    const png = fs.readFileSync(path.join(__dirname, 'fixtures/clipboard.png'));
    for (let id = 3; id <= 35; id++) {
        const file = path.join(directory, `${id}.png`);
        fs.writeFileSync(file, png);
        fs.utimesSync(file, id, id);
    }
    const newest = request(env, { operation: 'prepare', session: 'bounded', id: '2' });
    assert.equal(newest.status, 0, newest.stderr);
    assert.deepEqual(JSON.parse(newest.stdout).evicted, ['3', '4', '5']);
    assert.equal(fs.readdirSync(directory).filter(name => !name.startsWith('.')).length, 32);
    assert.ok(fs.existsSync(JSON.parse(newest.stdout).path));
});
