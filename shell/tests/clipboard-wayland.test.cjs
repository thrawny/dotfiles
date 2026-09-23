const { test } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn, spawnSync } = require('node:child_process');

const adapter = process.env.SHELL_CLIPBOARD_IMAGE_ADAPTER || path.resolve(__dirname, '../../bin/shell-clipboard-image');
const pause = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));

// All Wayland clients in this test receive the socket of our private headless
// compositor. Never fall back to a desktop display, even when startup fails.
test('image adapter preserves PNG and animated GIF bytes after cache cleanup on isolated Wayland', { timeout: 30000 }, async t => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'shell-image-wayland-'));
    fs.chmodSync(dir, 0o700);
    const runtime = path.join(dir, 'runtime');
    fs.mkdirSync(runtime, { mode: 0o700 });
    const env = {
        ...process.env,
        XDG_RUNTIME_DIR: runtime,
        TMPDIR: dir,
        XDG_CONFIG_HOME: path.join(dir, 'config'),
        XDG_CACHE_HOME: path.join(dir, 'cache'),
        WLR_BACKENDS: 'headless', WLR_RENDERER: 'pixman',
        WLR_LIBINPUT_NO_DEVICES: '1',
    };
    delete env.WAYLAND_DISPLAY;
    delete env.WAYLAND_SOCKET;
    delete env.DISPLAY;
    delete env.SWAYSOCK;
    delete env.I3SOCK;
    const config = path.join(dir, 'sway.conf');
    fs.writeFileSync(config, 'xwayland disable\noutput HEADLESS-1 resolution 320x240\nseat seat0 fallback true\n');
    let compositorLog = '';
    let startupError;
    const compositor = spawn('sway', ['--config', config], { env, stdio: ['ignore', 'pipe', 'pipe'] });
    compositor.on('error', error => { startupError = error; });
    compositor.stdout.on('data', data => { compositorLog += data.toString(); });
    compositor.stderr.on('data', data => { compositorLog += data.toString(); });
    const exited = new Promise(resolve => compositor.once('close', resolve));
    t.after(async () => {
        if (compositor.exitCode === null && compositor.signalCode === null) {
            compositor.kill('SIGTERM');
            const stopped = await Promise.race([exited.then(() => true), pause(2000).then(() => false)]);
            if (!stopped) {
                compositor.kill('SIGKILL');
                await exited;
            }
        }
        fs.rmSync(dir, { recursive: true, force: true });
    });
    let socket;
    const deadline = Date.now() + 12000;
    while (Date.now() < deadline) {
        if (startupError)
            throw startupError;
        socket = fs.readdirSync(runtime).find(name => /^wayland-\d+$/.test(name) && fs.statSync(path.join(runtime, name)).isSocket());
        if (socket)
            break;
        if (compositor.exitCode !== null)
            break;
        await pause(50);
    }
    assert.ok(socket, `Private headless compositor did not start:\n${compositorLog}`);
    env.WAYLAND_DISPLAY = path.join(runtime, socket);
    assert.ok(env.WAYLAND_DISPLAY.startsWith(runtime + path.sep));

    function run(command, args, input) {
        const result = spawnSync(command, args, { env, input, timeout: 5000 });
        assert.equal(result.status, 0, `${command} failed: ${result.error || ''}\n${result.stderr}`);
        return result.stdout;
    }
    // Synthetic 2×1 RGBA PNG and a two-frame 1×1 GIF. The animation must
    // survive instead of copying a flattened thumbnail.
    const fixtures = {
        png: Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAADklEQVR4nGP4z8AAQg0AD3oDfnfpf5cAAAAASUVORK5CYII=', 'base64'),
        gif: Buffer.from('R0lGODlhAQABAIAAAP8AAAAA/yH/C05FVFNDQVBFMi4wAwEAAAAh+QQABQAAACwAAAAAAQABAAACAkQBACH5BAAKAAAALAAAAAABAAEAAAICTAEAOw==', 'base64'),
    };
    const db = path.join(dir, 'history.db');
    for (const [extension, mime] of [['png', 'image/png'], ['gif', 'image/gif']]) {
        const original = fixtures[extension];
        run('cliphist', ['-db-path', db, 'store'], original);
        const id = run('cliphist', ['-db-path', db, 'list']).toString().split('\t', 1)[0];
        assert.match(id, /^\d+$/);
        const session = crypto.randomBytes(16).toString('hex');
        const request = operation => JSON.parse(run(adapter, ['--db-path', db], JSON.stringify({ operation, session, id })).toString());
        const prepared = request('prepare');
        assert.equal(prepared.mime, mime);
        assert.ok(fs.existsSync(prepared.path), 'Preview image was not prepared');
        assert.deepEqual(fs.readFileSync(prepared.path), original, 'Preparation changed the original image bytes');
        assert.equal(request('copy').copied, true);
        assert.equal(request('cleanup').cleaned, true);
        assert.equal(fs.existsSync(prepared.path), false, 'Cleanup retained preview files');
        const types = run('wl-paste', ['--list-types']).toString().trim().split('\n');
        assert.ok(types.includes(mime), `Missing original ${mime} clipboard target: ${types}`);
        const pasted = run('wl-paste', ['--no-newline', '--type', mime]);
        assert.deepEqual(pasted, original, `${extension.toUpperCase()} bytes changed during copy/cleanup/paste`);
    }
});
