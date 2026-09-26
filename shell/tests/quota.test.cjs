const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

for (const scenario of ['invalid', 'version', 'exit', 'missing']) {
    test(`quota service retains last data on ${scenario} failure`, t => {
        const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'shell-quota-'));
        t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
        fs.cpSync(path.resolve(__dirname, '../assets'), path.join(dir, 'assets'), { recursive: true });
        fs.cpSync(path.resolve(__dirname, '../services'), path.join(dir, 'services'), { recursive: true });
        fs.cpSync(path.resolve(__dirname, '../components'), path.join(dir, 'components'), { recursive: true });
        const config = path.join(dir, 'shell.qml');
        fs.writeFileSync(config, fs.readFileSync(path.join(__dirname, 'QuotaSmoke.qml'), 'utf8').replace('import "../services"', 'import "services"').replace('import "../components"', 'import "components"'));
        const fixture = path.join(dir, 'fixture.json');
        fs.writeFileSync(fixture, JSON.stringify({
            schema_version: 1, generated_at: '2026-09-23T12:00:00Z', providers: [
                { id: 'claude', name: 'Claude', available: true, summary: '72% 33% 5h',
                    updated_at: '2026-09-23T12:00:00Z',
                    windows: [{ id: 'primary', title: 'Session', used_percent: 72, expired: false,
                        severity: 'normal', reset_text: 'Resets in 5h', resets_at: '2026-09-23T17:00:00Z',
                        pace_text: null, expected_used_percent: null }],
                    cost: { used: 42.50, limit: 100, currency_code: 'USD', period: 'Monthly', resets_at: null },
                    reset_credits: { available_count: 1, credits: [{ title: 'Reset', available: true,
                        status: 'available', expires_at: '2026-09-24T12:00:00Z' }] },
                },
                { id: 'codex', available: false, windows: [] },
            ],
        }));
        const result = spawnSync('quickshell', ['-p', config], {
            env: { ...process.env, QT_QPA_PLATFORM: 'offscreen', WAYLAND_DISPLAY: '', DISPLAY: '',
                XDG_RUNTIME_DIR: dir, XDG_CONFIG_HOME: dir, XDG_CACHE_HOME: dir,
                QUOTA_TEST_CASE: scenario, QUOTA_FIXTURE: fixture },
            encoding: 'utf8', timeout: 10000,
        });
        assert.equal(result.status, 0, `${result.error || ''}\n${result.stdout}\n${result.stderr}`);
        assert.ok(result.stdout.includes('Configuration Loaded'), result.stdout + result.stderr);
        assert.doesNotMatch(result.stdout + result.stderr, /ReferenceError|TypeError|Unable to assign|Binding loop/);
    });
}
