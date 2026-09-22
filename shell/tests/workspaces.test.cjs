const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const model = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../services/WorkspaceOrder.js'), 'utf8'), model);

test('workspace positions ignore gaps and scratchpads', () => {
    const input = [
        { id: 5, name: 'agent-switch' }, { id: -98, name: 'special:term' },
        { id: 1, name: 'main' }, { id: 3, name: 'dotfiles' }, { id: 2, name: 'web' },
    ];
    assert.deepEqual(Array.from(model.ordered(input), ws => ws.id), [1, 2, 3, 5]);
    assert.equal(input[0].id, 5, 'does not mutate the compositor list');
});

test('named negative IDs remain ordinary workspaces', () => {
    const input = [{ id: 1, name: 'main' }, { id: -1337, name: 'project' }];
    assert.deepEqual(Array.from(model.ordered(input), ws => ws.id), [-1337, 1]);
});

test('number labels match Alt+1 through Alt+0, without repeating', () => {
    assert.equal(model.shortcut(0), '1');
    assert.equal(model.shortcut(8), '9');
    assert.equal(model.shortcut(9), '0');
    assert.equal(model.shortcut(10), '');
});

test('focus targets the ID, not its position, using Lua IPC', () => {
    assert.equal(model.focusRequest(5), 'hl.dsp.focus({workspace = "5"})');
    assert.throws(() => model.focusRequest('5"}); os.exit()'));
});

test('empty workspace model is valid', () => {
    assert.equal(model.ordered([]).length, 0);
});
