const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

test('quota popup loads original logos, stacks cards without clipping and selects/closes providers', t => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'shell-quota-visual-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    for (const component of ['services', 'components', 'assets'])
        fs.cpSync(path.resolve(__dirname, '..', component), path.join(dir, component), { recursive: true });
    fs.mkdirSync(path.join(dir, 'dotfiles'));
    fs.copyFileSync('nix/themes/monokai.json', path.join(dir, 'dotfiles/theme.json'));
    const config = path.join(dir, 'shell.qml');
    fs.writeFileSync(config, fs.readFileSync(path.join(__dirname, 'QuotaVisualSmoke.qml'), 'utf8')
        .replace('import "../services"', 'import "services"').replace('import "../components"', 'import "components"'));
    const quotaWindow = (id, title, used, reset, pace = null) => ({
        id, title, used_percent: used, expired: false, severity: used >= 90 ? 'critical' : used >= 75 ? 'warning' : 'normal',
        reset_description: reset, reset_text: 'Resets ' + reset, pace_text: pace,
    });
    const fixture = path.join(dir, 'fixture.json');
    fs.writeFileSync(fixture, JSON.stringify({
        schema_version: 1, generated_at: '2026-09-26T12:00:00Z', providers: [
            { id: 'claude', name: 'Claude', available: true, stale: false, error: null, summary: '72% 33% 3h',
                updated_at: '2026-09-26T12:00:00Z', identity: { plan: 'Max' }, usage_url: 'https://claude.ai/settings/usage',
                windows: [quotaWindow('primary', 'Current session', 72, 'in 3h'),
                    quotaWindow('secondary', 'Current week (all models)', 45, 'in 4 days', '12% in reserve · Lasts until reset'),
                    quotaWindow('tertiary', 'Current week (Sonnet only)', 33, 'in 6 days')],
                cost: { used: 42.50, limit: 100, currency_code: 'USD', period: 'Monthly' },
            },
            { id: 'codex', name: 'Codex', available: true, stale: false, error: null, summary: '85% 94% 1h',
                updated_at: '2026-09-26T12:00:00Z', identity: { plan: 'Pro' }, usage_url: 'https://chatgpt.com/codex/settings/usage',
                windows: [quotaWindow('primary', 'Current session', 85, 'in 1h'),
                    quotaWindow('secondary', 'Current week (all models)', 94, 'in 2 days', '42% in deficit · Runs out in 1h 30m')],
                reset_credits: { available_count: 1, credits: [{ available: true, expires_at: '2026-10-23T12:00:00Z' }] },
            },
        ],
    }));
    const screenshot = process.env.QUOTA_SCREENSHOT_PATH || path.join(dir, 'popup.png');
    const result = spawnSync('quickshell', ['-p', config], {
        env: { ...process.env, QT_QPA_PLATFORM: 'offscreen', WAYLAND_DISPLAY: '', WAYLAND_SOCKET: '', DISPLAY: '',
            XDG_RUNTIME_DIR: dir, XDG_CONFIG_HOME: dir, XDG_CACHE_HOME: dir,
            QUOTA_FIXTURE: fixture, QUOTA_SCREENSHOT: screenshot },
        encoding: 'utf8', timeout: 10000,
    });
    assert.equal(result.status, 0, `${result.error || ''}\n${result.stdout}\n${result.stderr}`);
    assert.ok(result.stdout.includes('Quota popup verified'), result.stdout + result.stderr);
    assert.ok(fs.statSync(screenshot).size > 1000, 'Popup screenshot was empty');
    assert.doesNotMatch(result.stdout + result.stderr, /ReferenceError|TypeError|Unable to assign|Binding loop|Cannot open/);
});
