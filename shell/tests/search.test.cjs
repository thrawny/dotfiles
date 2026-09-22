const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const search = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../services/Search.js'), 'utf8'), search);
const plain = value => JSON.parse(JSON.stringify(value));

test('app search ranks exact, prefix, substring, then subsequence', () => {
    const entries = ['My Ghostty', 'Ghostty Nightly', 'Ghost Terminal TTY', 'Ghostty'].map(name => ({ name }));
    assert.deepEqual(plain(search.apps(entries, 'ghostty')).map(row => row.name),
        ['Ghostty', 'Ghostty Nightly', 'My Ghostty', 'Ghost Terminal TTY']);
    assert.equal(search.apps(entries, 'zzzz').length, 0);
});
test('app search uses metadata, excludes hidden entries, and keeps launch objects', () => {
    const entry = { name: 'Ghostty', genericName: 'Terminal', keywords: ['Shell'] };
    const entries = [entry, { name: 'Hidden Shell', noDisplay: true }];
    assert.equal(search.apps(entries, 'shell')[0].entry, entry);
    assert.equal(search.apps(entries, 'terminal').length, 1);
    assert.equal(search.apps(entries, 'hidden').length, 0);
});
test('empty search sorts apps and caps results', () => {
    const entries = Array.from({ length: 100 }, (_, i) => ({ name: `App ${i}` }));
    assert.equal(search.apps(entries, '').length, 80);
    assert.equal(search.apps([{ name: 'Z' }, { name: 'A' }], '')[0].name, 'A');
});
test('terminal applications use Ghostty without interpreting arguments as shell code', () => {
    const command = ['example', 'an argument', '$(no-shell)'];
    assert.deepEqual(plain(search.appCommand({ command, runInTerminal: true })), ['ghostty', '-e', ...command]);
    assert.deepEqual(plain(search.appCommand({ command })), command);
    assert.deepEqual(plain(search.appCommand({ command: [], runInTerminal: true })), []);
});
test('clipboard parser accepts numeric IDs and preserves tabs and image previews', () => {
    const rows = plain(search.clipboardRows('9\thello\tworld\n7\t[[ binary data 4 KiB png 20x20 ]]\ninvalid\n;rm\tunsafe\n'));
    assert.equal(rows.length, 2);
    assert.equal(rows[0].id, '9');
    assert.equal(rows[0].name, 'hello\tworld');
    assert.ok(rows[1].name.includes('png'));
});
test('clipboard search ignores case, preserves recency, and does not fuzzy match', () => {
    const rows = search.clipboardRows('9\tHELLO World\n8\tHello\n7\tHelp Logs\n');
    assert.deepEqual(plain(search.clipboard(rows, ' HELLO ')).map(row => row.id), ['9', '8']);
    assert.equal(search.clipboard(rows, 'hlo').length, 0);
    assert.equal(search.clipboardRows('').length, 0);
});
test('mode chooser searches only the available modes', () => {
    assert.deepEqual(plain(search.modes('')).map(row => row.mode), ['apps', 'clipboard']);
    assert.equal(search.modes('clip')[0].mode, 'clipboard');
    assert.equal(search.modes('not-a-mode').length, 0);
});
