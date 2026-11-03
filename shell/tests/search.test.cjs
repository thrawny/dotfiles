const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const search = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../services/Search.js'), 'utf8'), search);
const plain = value => JSON.parse(JSON.stringify(value));




test('clipboard rows preserve IDs and tabs while hiding older binary entries', () => {
    const rows = plain(search.clipboardRows('9\thello\tworld\n7\t[[ binary data 4 KiB png 20x20 ]]\n6\t[[ binary data 3 B ]]\ninvalid\n;rm\tunsafe\n'));
    assert.deepEqual(rows.map(row => row.id), ['9']);
    assert.equal(rows[0].name, 'hello\tworld');
    assert.equal(search.clipboardRows('').length, 0);
    assert.equal(search.clipboardRows('3\tbad\u0000data\n').length, 0);
});
test('clipboard search is case-insensitive and retains recency rather than fuzzy matching', () => {
    const rows = search.clipboardRows('9\tHELLO World\n8\tHello\n7\tHelp Logs\n');
    assert.deepEqual(plain(search.clipboard(rows, ' HELLO ')).map(row => row.id), ['9', '8']);
    assert.equal(search.clipboard(rows, 'hlo').length, 0);
});
test('image history keeps order, dimensions, and type while rejecting unsupported binary rows', () => {
    const output = '9\ttext\n8\t[[ binary data 4 KiB png 20x30 ]]\n7\t[[ binary data 3 B ]]\n6\t[[ binary data 1 MiB jpeg 2048x1536 ]]\n';
    const rows = plain(search.clipboardRows(output, true));
    assert.deepEqual(rows.map(row => row.id), ['9', '8', '6']);
    assert.equal(rows[1].imageFormat, 'png');
    assert.equal(rows[1].imageSource, '');
    assert.deepEqual(plain(search.clipboard(rows, 'image')).map(row => row.id), ['8', '6']);
});
