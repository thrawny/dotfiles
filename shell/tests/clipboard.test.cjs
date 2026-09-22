const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const script = path.resolve(__dirname, '../../bin/shell-clipboard');

function fixture(t) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'shell-clipboard-test-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const db = path.join(dir, 'db');
    const log = path.join(dir, 'log');
    const payload = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0, 0xff, 0x0a]);
    fs.writeFileSync(path.join(dir, 'payload'), payload);
    fs.writeFileSync(db, '');
    function stub(name, body) {
        fs.writeFileSync(path.join(dir, name), '#!/usr/bin/env bash\nset -euo pipefail\n' + body, { mode: 0o755 });
    }
    stub('cliphist', `[[ "$1" == -db-path && "$2" == "$CLIPHIST_DB_PATH" ]] || exit 3
shift 2
printf '%s\\n' "$1" >> "$LOG"
case "$1" in
  decode|delete)
    # Require digits without a trailing newline, just like cliphist decode.
    cat > "$FIXTURE/id"
    [[ "$(wc -c < "$FIXTURE/id")" == 2 && "$(cat "$FIXTURE/id")" == 42 ]] || exit 4
    [[ "\${DECODE_FAIL:-}" != 1 ]] || exit 1
    [[ "$1" != decode ]] || cat "$FIXTURE/payload";;
  list) printf '42\\tfixture\\n';;
  store) cat > "$FIXTURE/stored";;
esac
`);
    stub('wl-copy', 'cat > "$FIXTURE/copied"\necho copy >> "$LOG"\n');
    return {
        dir, db, payload,
        log: () => fs.existsSync(log) ? fs.readFileSync(log, 'utf8') : '',
        run: (args, extra = {}) => spawnSync('bash', [script, ...args], {
            input: 'sample text', encoding: 'utf8', env: {
                ...process.env, PATH: dir + ':' + process.env.PATH,
                FIXTURE: dir, LOG: log, CLIPHIST_DB_PATH: db, TMPDIR: dir, ...extra,
            },
        }),
    };
}

test('copy sends only the ID to decode and preserves binary clipboard bytes', t => {
    const f = fixture(t);
    const result = f.run(['copy', '42']);
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(fs.readFileSync(path.join(f.dir, 'copied')), f.payload);
    assert.equal(f.log(), 'decode\ncopy\n');
    assert.ok(!fs.readdirSync(f.dir).some(name => name.startsWith('tmp.')));
});
test('failed decode does not overwrite the clipboard and removes temporary bytes', t => {
    const f = fixture(t);
    assert.equal(f.run(['copy', '42'], { DECODE_FAIL: '1' }).status, 1);
    assert.equal(f.log(), 'decode\n');
    assert.ok(!fs.existsSync(path.join(f.dir, 'copied')));
    assert.ok(!fs.readdirSync(f.dir).some(name => name.startsWith('tmp.')));
});
test('invalid IDs never reach cliphist', t => {
    const f = fixture(t);
    for (const id of ['', '-1', '42; touch /tmp/no', '42\n'])
        assert.equal(f.run(['copy', id]).status, 2);
    assert.equal(f.log(), '');
});
test('delete does not change the clipboard', t => {
    const f = fixture(t);
    assert.equal(f.run(['delete', '42']).status, 0);
    assert.equal(f.log(), 'delete\n');
});
test('sensitive clipboard offers are not persisted', t => {
    const f = fixture(t);
    assert.equal(f.run(['store'], { CLIPBOARD_STATE: 'sensitive' }).status, 0);
    assert.equal(f.log(), '');
    assert.equal(f.run(['store'], { CLIPBOARD_STATE: 'data' }).status, 0);
    assert.equal(fs.readFileSync(path.join(f.dir, 'stored'), 'utf8'), 'sample text');
});
test('a missing history is empty, while an existing one is listed', t => {
    const f = fixture(t);
    assert.equal(f.run(['list']).stdout, '42\tfixture\n');
    fs.unlinkSync(f.db);
    const result = f.run(['list']);
    assert.equal(result.status, 0);
    assert.equal(result.stdout, '');
});

test('real cliphist round-trips text and binary data in an isolated database', t => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'shell-cliphist-integration-'));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    // Only wl-copy is stubbed. Never read or write the desktop clipboard.
    fs.writeFileSync(path.join(dir, 'wl-copy'), '#!/usr/bin/env bash\ncat > "$COPIED"\n', { mode: 0o755 });
    const env = {
        ...process.env, PATH: dir + ':' + process.env.PATH,
        XDG_CONFIG_HOME: dir, CLIPHIST_DB_PATH: path.join(dir, 'db'),
        COPIED: path.join(dir, 'copied'), CLIPBOARD_STATE: 'data',
    };
    const run = (args, input) => {
        const result = spawnSync('bash', [script, ...args], { env, input });
        assert.equal(result.status, 0, result.stderr.toString());
        return result.stdout;
    };
    assert.equal(run(['list']).length, 0);
    const payloads = [Buffer.from('sample text\nwith a trailing newline\n'), Buffer.from([0x89, 0x50, 0x4e, 0x47, 0, 0xff, 0x0a])];
    for (const payload of payloads) {
        run(['store'], payload);
        const id = run(['list']).toString().split('\t')[0];
        run(['copy', id]);
        assert.deepEqual(fs.readFileSync(env.COPIED), payload);
    }
    const id = run(['list']).toString().split('\t')[0];
    run(['delete', id]);
    assert.equal(run(['list']).toString().trim().split('\n').length, 1);
});
