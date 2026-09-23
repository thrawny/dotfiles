const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const smoke = path.resolve(__dirname, 'ClipboardSmoke.qml');

for (const scenario of ['roundtrip', 'cancel', 'empty', 'broken-db']) {
    test(`direct QML/cliphist integration: ${scenario}`, t => {
        const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'shell-clipboard-qml-'));
        t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
        const db = path.join(dir, 'db');
        // Quickshell resolves QML modules beneath its entrypoint directory.
        fs.mkdirSync(path.join(dir, 'services'));
        for (const name of ['Clipboard.qml', 'Search.js']) {
            fs.copyFileSync(path.resolve(__dirname, '../services', name), path.join(dir, 'services', name));
        }
        fs.writeFileSync(path.join(dir, 'services/qmldir'), 'singleton Clipboard 1.0 Clipboard.qml\n');
        const config = path.join(dir, 'shell.qml');
        fs.writeFileSync(config, fs.readFileSync(smoke, 'utf8').replace('import "../services"', 'import "services"'));
        const env = {
            ...process.env,
            QT_QPA_PLATFORM: 'offscreen', WAYLAND_DISPLAY: '', DISPLAY: '',
            XDG_RUNTIME_DIR: dir, XDG_CONFIG_HOME: dir,
            XDG_CACHE_HOME: dir, CLIPHIST_DB_PATH: db,
            CLIPBOARD_TEST_CASE: scenario,
        };
        if (scenario === 'broken-db') {
            fs.writeFileSync(db, 'not a cliphist database');
        } else if (scenario !== 'empty') {
            const fixtures = [
                Buffer.from('  Clipboard fixture 🙂\nsecond line\n\n'),
                fs.readFileSync(path.join(__dirname, 'fixtures/clipboard.png')),
                Buffer.from([0, 0xff, 0x89, 0x50]),
            ];
            for (const input of fixtures) {
                const stored = spawnSync('cliphist', ['-db-path', db, 'store'], { env, input });
                assert.equal(stored.status, 0, stored.stderr.toString());
            }
        }
        const result = spawnSync('quickshell', ['-p', config], { env, encoding: 'utf8', timeout: 10000 });
        assert.equal(result.status, 0, `${result.error || ''}\n${result.stdout}\n${result.stderr}`);
        // A successful QML exit alone must not hide a startup/import failure.
        assert.ok(result.stdout.includes('Configuration Loaded'), result.stdout + result.stderr);
    });
}
