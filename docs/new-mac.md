# Bootstrap a new Mac

For an Apple Silicon Mac. Install Nix, add this Mac to the repo if needed, then run the first Home Manager switch. After that, use `just switch`.

For the existing `thrawnym1` target, use the [nix-darwin and remote access guide](mac-remote-access.md) instead. That target integrates Home Manager into nix-darwin and needs an administrator password for system switches.

## Interactive setup

Install Apple's command line tools with `xcode-select --install`, then clone the repo and start the walkthrough:

```sh
git clone https://github.com/thrawny/dotfiles.git "$HOME/dotfiles"
cd "$HOME/dotfiles"
bin/bootstrap-mac
```

The script runs with the Bash included in macOS. Nix and `just` are not required to start it. It checks prerequisites, pauses for the Determinate GUI installer, offers to create a missing Mac target, and waits while you review or edit the repo. It verifies the target's username and paths before asking to run the first switch.

Answer its prompts in Terminal. Do GUI setup and repo edits in another window, then press Enter to continue. Type `q` at a pause or press Ctrl-C to stop; rerun the script to resume from the current state. The script leaves repo edits in place and does not commit them. It asks you to stage new target files yourself.

Once `just` is available, `just bootstrap-mac` starts the same walkthrough. The steps below are the manual alternative. The script uses timestamped backup suffixes for conflicting dotfiles.

## 1. Install the prerequisites

In Terminal, install Apple's command line tools and wait for the installer to finish:

```sh
xcode-select --install
```

Download and open the [Determinate Nix macOS installer](https://docs.determinate.systems/). Complete its GUI steps and administrator authentication. Use the GUI directly; running the package in a background session can hit macOS permission errors.

Open a new Terminal window and check:

```sh
nix --version
```

The output should say `Determinate Nix`.

## 2. Clone the dotfiles

```sh
git clone https://github.com/thrawny/dotfiles.git "$HOME/dotfiles"
cd "$HOME/dotfiles"
```

Keep the checkout here. Several configurations link directly to its files. Run the remaining commands from this repo root.

## 3. Add this Mac as a target

Find the target name, macOS username, and checkout location:

```sh
mac_target="$(hostname | sed 's/\.local$//')"
printf 'Target: %s\nUsername: %s\nCheckout: %s\n' "$mac_target" "$(id -un)" "$PWD"
```

`just switch` uses this target name. If it already exists under `homeConfigurations` in `nix/flake.nix`, check its username and checkout path, then skip to step 4.

Otherwise, copy the existing Mac's settings:

```sh
mkdir -p "nix/hosts/$mac_target"
cp nix/hosts/thrawnym1/default.nix "nix/hosts/$mac_target/default.nix"
```

Edit the copied file. Set `username` to the username printed above and `dotfiles` to the checkout path. Keep `homeSource = "repo";` and check the Git name and email.

In `nix/flake.nix`, add this entry **inside the existing `homeConfigurations = { ... };` block**, alongside `thrawnym1`. Replace both occurrences of `YOUR-MAC-NAME` with the target printed above:

```nix
"YOUR-MAC-NAME" = mkHomeConfiguration {
  pkgs = nixpkgs.legacyPackages.aarch64-darwin;
  modules = [ ./home/darwin/default.nix ];
  extraSpecialArgs = import ./hosts/YOUR-MAC-NAME/default.nix;
};
```

Make the new file visible to the Git-backed flake:

```sh
git add "nix/hosts/$mac_target/default.nix" nix/flake.nix
```

Staging is enough for the first switch. Commit and push the target later so the next checkout includes it.

## 4. Run the first switch

You do not need Home Manager or `just` installed yet. This command runs the Home Manager version pinned by the repo:

```sh
mac_target="$(hostname | sed 's/\.local$//')"
mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles"
nix run --inputs-from ./nix home-manager -- \
  switch -b bak --flake "./nix#$mac_target"
```

Run this as your normal user, without `sudo`. It installs the configured tools, including Home Manager and `just`, links the dotfiles, and applies the configured macOS defaults. The first run can take a while.

Existing regular files that conflict with managed dotfiles get a `.bak` suffix. If a `.bak` file already exists and blocks activation, move that backup somewhere safe and rerun the command. Home Manager refuses to back up conflicting symlinks automatically. Move the reported link to an unused backup name yourself, then retry; leave its destination intact.

Open a new Terminal window, then verify:

```sh
nix --version
nix store info
home-manager --version
just --version
```

## 5. Finish the Mac setup

- Install [Ghostty](https://ghostty.org/download) and [AeroSpace](https://nikitabobko.github.io/AeroSpace/guide#installation). This repo configures them but does not install their Mac apps. Follow AeroSpace's permission prompts when launching it.
- Install CaskaydiaMono Nerd Font through Font Book for the configured terminal font.
- Sign in to your development services and restore any SSH keys or credentials you need. The first switch seeds local Claude, Codex, and Pi settings from the repo's examples; existing credentials and private local settings are not in Git.
- Log out and back in to refresh the session and macOS settings.

## Everyday use

```sh
cd "$HOME/dotfiles"
just switch
```

If you rename the Mac, update its target too. To select a compatible target explicitly, use `home-manager switch -b bak --flake ./nix#TARGET` from the repo root.

Determinate manages Nix itself. Put any custom daemon settings in `/etc/nix/nix.custom.conf`, which needs `sudo` to edit. Ordinary Home Manager switches do not need `sudo`.
