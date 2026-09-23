const { test } = require('node:test');
const assert = require('node:assert/strict');
const { counters, rates, bytes } = require('../services/NetworkStats.js');

test('network counters use active interfaces and handle resets and new devices', () => {
    const previous = counters(' wlan0: 1000 0 0 0 0 0 0 0 2000\n lo: 99999 0 0 0 0 0 0 0 99999', ['wlan0']);
    const next = counters(' wlan0: 4000 0 0 0 0 0 0 0 3500\n eth0: 50000 0 0 0 0 0 0 0 50000', ['wlan0', 'eth0']);
    assert.deepEqual(rates(previous, next, 3), { rx: 1000, tx: 500 });
    assert.deepEqual(rates(next, previous, 3), { rx: 0, tx: 0 });
    assert.deepEqual(rates(previous, next, 0), { rx: 0, tx: 0 });
    assert.equal(bytes(2048), '2.0 KiB/s');
});
