const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const Qt = {
    ControlModifier: 0x04000000,
    Key_Up: 0x01000013, Key_Down: 0x01000015,
    Key_K: 0x4b, Key_J: 0x4a, Key_P: 0x50, Key_N: 0x4e,
};
const keys = vm.createContext({ Qt });
vm.runInContext(fs.readFileSync(path.join(__dirname, '../components/PickerKeys.js'), 'utf8'), keys);

test('shared picker navigation accepts Ctrl+K/J and existing Ctrl+P/N aliases', () => {
    for (const key of [Qt.Key_K, Qt.Key_P])
        assert.equal(keys.direction(key, Qt.ControlModifier), -1);
    for (const key of [Qt.Key_J, Qt.Key_N])
        assert.equal(keys.direction(key, Qt.ControlModifier), 1);
});
test('arrows navigate, while unmodified letters remain available for search', () => {
    assert.equal(keys.direction(Qt.Key_Up, 0), -1);
    assert.equal(keys.direction(Qt.Key_Down, 0), 1);
    for (const key of [Qt.Key_K, Qt.Key_J, Qt.Key_P, Qt.Key_N])
        assert.equal(keys.direction(key, 0), 0);
    assert.equal(keys.direction(0x41, Qt.ControlModifier), 0);
});
