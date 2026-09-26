const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

for (const scenario of ['open', 'worktree', 'missing-directory', 'launch-failure', 'missing-launcher', 'timeout', 'cancel', 'cancel-action', 'reopen']) {
    test(`QML project picker: ${scenario}`, t => {
        const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'shell-projects-'));
        t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
        const tools = path.join(dir, 'tools');
        const services = path.join(dir, 'services');
        fs.mkdirSync(tools);
        fs.mkdirSync(services);
        for (const name of ['Projects.qml', 'ProjectWorktree.js'])
            fs.copyFileSync(path.join(__dirname, '../services', name), path.join(services, name));
        fs.writeFileSync(path.join(services, 'qmldir'), 'singleton Projects 1.0 Projects.qml\n');
        const config = path.join(dir, 'shell.qml');
        fs.writeFileSync(config, fs.readFileSync(path.join(__dirname, 'ProjectsSmoke.qml'), 'utf8').replace('import "../services"', 'import "services"'));
        const repo = path.join(dir, 'code/project with spaces');
        const env = {
            ...process.env,
            HOME: dir, GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: '/dev/null',
            QT_QPA_PLATFORM: 'offscreen', WAYLAND_DISPLAY: '', DISPLAY: '',
            XDG_RUNTIME_DIR: dir, XDG_CONFIG_HOME: dir, XDG_CACHE_HOME: dir,
            PROJECTS_TEST_CASE: scenario,
            PATH: tools + path.delimiter + process.env.PATH,
        };
        for (const rel of ['code/project with spaces', 'work/acme/code/nested/project', 'elsewhere/history', 'work/acme/not-code/ignored']) {
            const target = path.join(dir, rel);
            fs.mkdirSync(target, { recursive: true });
            const result = spawnSync('git', ['init', '--initial-branch=main', target], { env, encoding: 'utf8' });
            assert.equal(result.status, 0, result.stderr);
        }
        fs.mkdirSync(path.join(repo, 'subdir'));
        fs.symlinkSync(repo, path.join(dir, 'alias'));
        const commit = spawnSync('git', ['-C', repo, '-c', 'user.name=Test', '-c', 'user.email=test@example.com', '-c', 'commit.gpgsign=false', 'commit', '--allow-empty', '-m', 'initial'], { env, encoding: 'utf8' });
        assert.equal(commit.status, 0, commit.stderr);
        function stub(name, body) {
            fs.writeFileSync(path.join(tools, name), `#!${process.execPath}\n${body}`, { mode: 0o755 });
        }
        const history = [path.join(dir, 'alias/subdir'), repo, path.join(dir, 'elsewhere/history'), path.join(dir, 'missing')].join('\n') + '\n';
        stub('zoxide', `setTimeout(() => process.stdout.write(${JSON.stringify(history)}), ${['cancel', 'reopen'].includes(scenario) ? 200 : 0});`);
        const log = path.join(dir, 'launch.json');
        stub('hyprland-project', `require('node:fs').writeFileSync(${JSON.stringify(log)}, JSON.stringify(process.argv.slice(2))); ${scenario === 'launch-failure' ? 'console.error("Workspace launch failed"); process.exit(1);' : ''}`);
        if (scenario === 'cancel-action')
            stub('hyprland-project', `require('node:fs').writeFileSync(${JSON.stringify(log)}, JSON.stringify(process.argv.slice(2))); setTimeout(() => {}, 300);`);
        if (scenario === 'timeout')
            stub('hyprland-project', 'setTimeout(() => {}, 3000);');
        if (scenario === 'missing-launcher')
            fs.writeFileSync(path.join(tools, 'hyprland-project'), '#!/no-such-interpreter\n');
        const result = spawnSync('quickshell', ['-p', config], { env, encoding: 'utf8', timeout: 12000 });
        assert.equal(result.status, 0, `${result.error || ''}\n${result.stdout}\n${result.stderr}`);
        assert.ok(result.stdout.includes('Configuration Loaded'), result.stdout + result.stderr);
        if (['open', 'reopen', 'launch-failure'].includes(scenario) || (scenario === 'cancel-action' && fs.existsSync(log)))
            assert.deepEqual(JSON.parse(fs.readFileSync(log, 'utf8')), ['--terminals', '1', '--', repo]);
        else if (scenario === 'worktree')
            assert.deepEqual(JSON.parse(fs.readFileSync(log, 'utf8')), ['--terminals', '1', '--name', 'project with spaces/feature/nested', '--', repo + '-worktrees/feature/nested']);
        else
            assert.equal(fs.existsSync(log), false);
    });
}

test('Alt+P replaces the terminal picker binding and exposes launcher IPC', () => {
    const binds = fs.readFileSync(path.join(__dirname, '../../config/hypr/lua/binds.lua'), 'utf8');
    assert.ok(binds.includes('bind("ALT + P", dsp.exec_cmd("quickshell ipc -c dotfiles call launcher projects"))'));
    assert.ok(!binds.includes('ghostty --title=project-picker'));
    assert.ok(fs.readFileSync(path.join(__dirname, '../shell.qml'), 'utf8').includes('Launcher.toggleProjects()'));
});
