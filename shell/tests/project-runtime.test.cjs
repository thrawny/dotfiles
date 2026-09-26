const { test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

// Evaluate the actual service declaration without fetching/building the flake.
// Package values are irrelevant here; the PATH composition is the regression.
test('the systemd shell PATH can execute the checkout project launcher', () => {
    const root = path.resolve(__dirname, '../..');
    const expression = `let
      root = builtins.getEnv "PROJECT_TEST_ROOT";
      module = import (builtins.toPath (root + "/nix/home/nixos/hyprland.nix")) {
        dotfiles = root;
        config.home.username = builtins.getEnv "USER";
        agent-switch = null;
        quotabar.packages.fixture.default = "/fixture/quotabar";
        pkgs = {
          stdenv.hostPlatform.system = "fixture";
          callPackage = file: args: "/fixture/package";
          lib.makeBinPath = packages:
            builtins.concatStringsSep ":" (map (package: package + "/bin") packages);
        };
      };
    in module.systemd.user.services.dotfiles-shell.Service.Environment`;
    const result = spawnSync('nix-instantiate', ['--eval', '--strict', '--json', '--expr', expression], {
        env: { ...process.env, PROJECT_TEST_ROOT: root }, encoding: 'utf8', timeout: 10000,
    });
    assert.equal(result.status, 0, `${result.error || ''}\n${result.stderr}`);
    const assignment = JSON.parse(result.stdout);
    assert.ok(assignment.startsWith('PATH='));
    const servicePath = assignment.slice(5);
    assert.ok(servicePath.split(':').includes(path.join(root, 'bin')), 'Systemd omits the checkout commands from PATH');
    // Do not append the interactive shell PATH: that hid the missing command.
    const help = spawnSync('hyprland-project', ['--help'], {
        env: { ...process.env, PATH: servicePath }, encoding: 'utf8', timeout: 5000,
    });
    assert.equal(help.status, 0, `${help.error || ''}\n${help.stderr}`);
    assert.match(help.stdout, /Usage: hyprland-project/);
});
