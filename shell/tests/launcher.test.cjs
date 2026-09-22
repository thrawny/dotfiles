const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const script = path.resolve(__dirname, '../..', 'bin/dotfiles-bar');

function run(t, mode, extra = {}) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dotfiles-bar-test-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    function stub(name, body) {
        fs.writeFileSync(path.join(dir, name), '#!/usr/bin/env bash\n' + body, { mode: 0o755 });
    }
    stub('quickshell', `printf 'qs %s\\n' "$*" >> "$LOG"
if [[ "$1" == ipc ]]; then echo "\${READY:-ready}"; fi
if [[ "$*" == *--daemonize* && "\${LAUNCH_FAIL:-}" == 1 ]]; then exit 1; fi
`);
    stub('pkill', 'echo stopped-waybar >> "$LOG"\n');
    stub('pgrep', 'exit 1\n');
    stub('hyprctl', 'echo started-waybar >> "$LOG"\n');
    stub('sleep', 'true\n');
    const log = path.join(dir, 'log');
    const result = spawnSync('bash', [script, mode], {
        encoding: 'utf8', env: {
            ...process.env, PATH: dir + ':' + process.env.PATH,
            SANDBOX: '0', HYPRLAND_INSTANCE_SIGNATURE: 'test',
            DOTFILES_SHELL_DIR: '/test/shell', LOG: log, ...extra,
        },
    });
    return { ...result, log: fs.existsSync(log) ? fs.readFileSync(log, 'utf8') : '' };
}

test('successful readiness check precedes stopping Waybar', t => {
    const result = run(t, 'quickshell');
    assert.equal(result.status, 0, result.stderr);
    assert.ok(result.log.indexOf('call shell ping') < result.log.indexOf('stopped-waybar'));
});
test('failed initial launch preserves or starts Waybar', t => {
    const result = run(t, 'quickshell', { LAUNCH_FAIL: '1' });
    assert.equal(result.status, 1);
    assert.ok(result.log.includes('started-waybar'));
    assert.ok(!result.log.includes('stopped-waybar'));
});
test('failed readiness stops broken shell, never stops Waybar', t => {
    const result = run(t, 'quickshell', { READY: 'theme-unavailable' });
    assert.equal(result.status, 1);
    assert.ok(result.log.includes('qs kill -p /test/shell'));
    assert.ok(!result.log.includes('stopped-waybar'));
});
test('fallback starts Waybar before stopping the shell', t => {
    const result = run(t, 'waybar');
    assert.equal(result.status, 0);
    assert.ok(result.log.indexOf('started-waybar') < result.log.indexOf('qs kill'));
});
test('sandbox refuses desktop lifecycle changes', t => {
    const result = run(t, 'quickshell', { SANDBOX: '1' });
    assert.equal(result.status, 1);
    assert.equal(result.log, '');
});
