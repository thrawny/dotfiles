const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

test('project launcher modes, branch/path entry and layout', t => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'shell-launcher-projects-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    for (const component of ['services', 'components', 'modules/launcher'])
        fs.cpSync(path.resolve(__dirname, '..', component), path.join(dir, component), { recursive: true });
    fs.mkdirSync(path.join(dir, 'dotfiles'));
    fs.copyFileSync('nix/themes/monokai.json', path.join(dir, 'dotfiles/theme.json'));
    fs.mkdirSync(path.join(dir, 'tools'));
    fs.writeFileSync(path.join(dir, 'tools/zoxide'), `#!${process.execPath}\nprocess.exit(0);`, { mode: 0o755 });
    const repo = path.join(dir, 'code/widgets');
    fs.mkdirSync(repo, { recursive: true });
    const screenshot = process.env.PROJECTS_SCREENSHOT_PATH || path.join(dir, 'projects.png');
    const env = {
        ...process.env, HOME: dir, GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: '/dev/null',
        QT_QPA_PLATFORM: 'offscreen', WAYLAND_DISPLAY: '', WAYLAND_SOCKET: '', DISPLAY: '',
        HYPRLAND_INSTANCE_SIGNATURE: '', XDG_RUNTIME_DIR: dir, XDG_CONFIG_HOME: dir, XDG_CACHE_HOME: dir,
        CLIPHIST_DB_PATH: path.join(dir, 'clipboard.db'), PROJECTS_SCREENSHOT: screenshot,
        PATH: path.join(dir, 'tools') + path.delimiter + process.env.PATH,
    };
    const init = spawnSync('git', ['init', '--initial-branch=main', repo], { env, encoding: 'utf8' });
    assert.equal(init.status, 0, init.stderr);
    const config = path.join(dir, 'shell.qml');
    fs.writeFileSync(config, fs.readFileSync(path.join(__dirname, 'LauncherProjectsSmoke.qml'), 'utf8')
        .replace('import "../services"', 'import "services"').replace('import "../modules/launcher"', 'import "modules/launcher"'));
    const result = spawnSync('quickshell', ['-p', config], { env, encoding: 'utf8', timeout: 10000 });
    assert.equal(result.status, 0, `${result.error || ''}\n${result.stdout}\n${result.stderr}`);
    assert.ok(result.stdout.includes('Project launcher verified'), result.stdout + result.stderr);
    assert.ok(fs.statSync(screenshot).size > 1000, 'Project picker screenshot was empty');
    assert.doesNotMatch(result.stdout + result.stderr, /ReferenceError|TypeError|Unable to assign|Binding loop|Cannot open/);
});
