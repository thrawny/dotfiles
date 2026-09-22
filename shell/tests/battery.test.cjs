const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const battery = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../services/BatteryIcon.js'), 'utf8'), battery);

test('battery fill follows state of charge in ten-percent steps', () => {
    assert.equal(battery.icon(0), '󰂎');
    assert.equal(battery.icon(0.35), '󰁼');
    assert.equal(battery.icon(0.5), '󰁾');
    assert.equal(battery.icon(0.99), '󰂂');
    assert.equal(battery.icon(1), '󰁹');
});

test('battery levels clamp out-of-range readings and handle unknown charge', () => {
    assert.equal(battery.icon(-1), battery.icon(0));
    assert.equal(battery.icon(2), battery.icon(1));
    assert.equal(battery.icon(NaN), '󰂑');
});
