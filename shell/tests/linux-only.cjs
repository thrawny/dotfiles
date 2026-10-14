// Quickshell, cliphist and sway build only for Linux, so tests that run them skip elsewhere.
module.exports = process.platform !== 'linux' && 'needs Quickshell, cliphist and sway, which are Linux-only';
