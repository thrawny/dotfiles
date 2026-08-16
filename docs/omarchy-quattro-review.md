# Omarchy adoption review

Research snapshot: 2026-08-15. Compared the whole official Omarchy repository at [`quattro` commit `9b72edcc`](https://github.com/basecamp/omarchy/tree/9b72edcc94513cba016f145b1ac4ffdaea54b577), one commit after [`v4.0.0`](https://github.com/basecamp/omarchy/releases/tag/v4.0.0), with this dotfiles repository at [`6e00c1a`](https://github.com/thrawny/dotfiles/tree/6e00c1a853a1ec7eb09651cb8a72b9664e936913). Omarchy claims below cite first-party documentation or source pinned to that reviewed commit or the release commit (`f0020448`, released 2026-08-14), as appropriate; the separate Omarchy clone remains fast-forwarded to the live branch.

## Bottom line

The best thing to copy is Omarchy's product thinking: small desktop actions feel like one system because they share a command registry, launcher surface, palette, notifications, and sensible handoffs between apps. Keep Niri, Walker, Waybar, Mako, and the declarative Nix base; add the portable workflows around them.

Recommended order:

1. Make one data-first theme palette and migrate the existing visual surfaces without changing their current appearance.
2. Add a curated Walker **Actions** menu as the Niri-native home for the useful Omarchy-style commands.
3. Add Moonlight to the Z13, then Taildrop send/receive, reminders, Wi-Fi QR sharing, and media transcode/share.
4. Add LocalSend if transfers to phones or non-tailnet machines are common.
5. Add declarative Helium web-app launchers and trial the browser-to-`yt-dlp` action.
6. Fold in the earlier capture, DDC brightness, and mpv MPRIS wins; leave the system-pressure experiments until the daily conveniences have landed.

Do not port the complete Quickshell/Hyprland desktop or its plugin runtime.

## Current Omarchy stack

This inventory was verified at [`9b72edcc`](https://github.com/basecamp/omarchy/tree/9b72edcc94513cba016f145b1ac4ffdaea54b577), one commit after `v4.0.0`; the stack boundary was rechecked after syncing the clone to later `quattro` commits.

**Walker is gone from Omarchy.** Quattro retired Walker/Elephant together with Waybar, Mako, SwayOSD, hyprlock, hypridle, swaybg, and polkit-gnome; the upgrade removes their packages and backs up the old UI configs ([release statement](https://github.com/basecamp/omarchy/releases/tag/v4.0.0#the-quattro-release), [retired packages](https://github.com/basecamp/omarchy/blob/9b72edcc94513cba016f145b1ac4ffdaea54b577/bin/omarchy-upgrade-to-quattro#L812-L865), [config retirement](https://github.com/basecamp/omarchy/blob/9b72edcc94513cba016f145b1ac4ffdaea54b577/bin/omarchy-upgrade-to-quattro#L1911-L1920)). `Super+Space` now opens an Omarchy-authored Quickshell command menu whose Apps provider is the native launcher; the dedicated apps-only view is `Super+Alt+Space` ([bindings](https://github.com/basecamp/omarchy/blob/9b72edcc94513cba016f145b1ac4ffdaea54b577/default/hypr/bindings/utilities.lua#L1-L4), [application library](https://github.com/basecamp/omarchy/blob/9b72edcc94513cba016f145b1ac4ffdaea54b577/shell/services/AppLibrary.qml#L1-L10)).

| Layer | What runs now | Ownership boundary |
| --- | --- | --- |
| Core platform | Arch Linux; SDDM into a UWSM-managed Hyprland Wayland session; systemd, XDG portals, NetworkManager, PipeWire/WirePlumber, and standard Linux services | Third-party platform, selected and heavily configured by Omarchy. Omarchy's own manual names Arch, Hyprland, and Quickshell as the foundation ([overview](https://github.com/basecamp/omarchy/blob/9b72edcc94513cba016f145b1ac4ffdaea54b577/manual/01-welcome-to-omarchy.md#L1-L5)); its session entry starts Hyprland through UWSM ([session entry](https://github.com/basecamp/omarchy/blob/9b72edcc94513cba016f145b1ac4ffdaea54b577/default/wayland-sessions/omarchy.desktop#L1-L4)), and the pinned package manifest shows the concrete service components ([base packages](https://github.com/basecamp/omarchy/blob/9b72edcc94513cba016f145b1ac4ffdaea54b577/install/omarchy-base.packages#L42-L64), [session packages](https://github.com/basecamp/omarchy/blob/9b72edcc94513cba016f145b1ac4ffdaea54b577/install/omarchy-base.packages#L105-L144)). |
| Desktop shell | One long-running Quickshell process hosting the bar, launcher/menu, wallpaper, notification daemon/history, clipboard and emoji pickers, OSD, idle/lock, polkit prompt, and audio/Bluetooth/network/display/power/weather/service panels | Quickshell is the third-party toolkit; the QML/JS shell, shared UI library, plugin registry, and built-in `omarchy.*` plugins are Omarchy-authored ([architecture](https://github.com/basecamp/omarchy/blob/9b72edcc94513cba016f145b1ac4ffdaea54b577/shell/README.md#L1-L44), [default bar composition](https://github.com/basecamp/omarchy/blob/9b72edcc94513cba016f145b1ac4ffdaea54b577/config/omarchy/shell.json#L1-L65)). Third-party shell plugins are supported, but execute unsandboxed inside that same process ([plugin trust model](https://github.com/basecamp/omarchy/blob/9b72edcc94513cba016f145b1ac4ffdaea54b577/docs/omarchy-shell.md#L43-L78)). |
| Control and integration layer | The `omarchy` dispatcher and `omarchy-*` scripts; the Lua Hyprland configuration/helpers; JSONC command tree; semantic theme renderer; update/install/migration flows; capture, sharing, web-app, hardware, power, networking, and agent integrations | This glue is the largest custom part of Omarchy. The CLI exposes those operations as stable groups ([CLI groups](https://github.com/basecamp/omarchy/blob/9b72edcc94513cba016f145b1ac4ffdaea54b577/bin/omarchy#L29-L94)); the nested command registry is also Omarchy data/code, not a feature supplied by Quickshell ([menu schema and roots](https://github.com/basecamp/omarchy/blob/9b72edcc94513cba016f145b1ac4ffdaea54b577/default/omarchy/omarchy-menu.jsonc#L1-L28)). |
| Omarchy standalone apps and configurations | Omawrite, Omacut, and Omacalc are the explicitly first-party desktop apps; `omarchy-nvim` is Omarchy's configured Neovim distribution built on third-party LazyVim. Herdr is a related `omacom-io` standalone terminal workspace manager with an Omarchy configuration | These are separate projects/packages, not Quickshell plugins ([Omawrite](https://github.com/basecamp/omarchy/blob/9b72edcc94513cba016f145b1ac4ffdaea54b577/manual/22-guis.md#L21-L25), [Omacalc](https://github.com/basecamp/omarchy/blob/9b72edcc94513cba016f145b1ac4ffdaea54b577/manual/22-guis.md#L62-L66), [Omacut](https://github.com/basecamp/omarchy/blob/9b72edcc94513cba016f145b1ac4ffdaea54b577/manual/22-guis.md#L92-L96), [Neovim boundary](https://github.com/basecamp/omarchy/blob/9b72edcc94513cba016f145b1ac4ffdaea54b577/manual/16-neovim.md#L7-L10), [Herdr](https://github.com/basecamp/omarchy/blob/9b72edcc94513cba016f145b1ac4ffdaea54b577/manual/21-tuis.md#L25-L29)). |
| Notable third-party defaults | Foot, Chromium, Nautilus, Neovim, Obsidian, LibreOffice, Pinta, imv/mpv/Evince, OBS Studio, Kdenlive, LocalSend, Moonlight, tmux, btop, and lazygit/lazydocker | Omarchy packages, themes, binds, and joins these apps into workflows rather than owning them. Examples include its Chromium native-messaging extensions ([browser integration](https://github.com/basecamp/omarchy/blob/9b72edcc94513cba016f145b1ac4ffdaea54b577/manual/23-browsers.md#L19-L29)), Nautilus LocalSend actions ([file workflow](https://github.com/basecamp/omarchy/blob/9b72edcc94513cba016f145b1ac4ffdaea54b577/manual/22-guis.md#L39-L54)), and Chromium-backed desktop entries for HEY, Basecamp, WhatsApp, Google apps, X, YouTube, Zoom, and Discord ([web-app model](https://github.com/basecamp/omarchy/blob/9b72edcc94513cba016f145b1ac4ffdaea54b577/manual/25-web-apps.md#L1-L15), [shipped set](https://github.com/basecamp/omarchy/blob/9b72edcc94513cba016f145b1ac4ffdaea54b577/manual/25-web-apps.md#L17-L75)). |

One especially relevant custom integration is its keybinding search. `omarchy-menu-keybindings` reads the resolved live Hyprland binds, supplements missing Lua metadata from the user's source, normalizes the rows, opens them in the shell's searchable selection mode, and can dispatch the selected binding ([live/source adapter](https://github.com/basecamp/omarchy/blob/9b72edcc94513cba016f145b1ac4ffdaea54b577/bin/omarchy-menu-keybindings#L1-L14), [normalization](https://github.com/basecamp/omarchy/blob/9b72edcc94513cba016f145b1ac4ffdaea54b577/bin/omarchy-menu-keybindings#L260-L318), [search and dispatch](https://github.com/basecamp/omarchy/blob/9b72edcc94513cba016f145b1ac4ffdaea54b577/bin/omarchy-menu-keybindings#L583-L596)). That validates the proposed direction here, but Omarchy's implementation is Hyprland-specific and keeps tmux/Herdr in separate viewers. For this setup, use the same adapter/catalog/view pattern with **Niri and xremap adapters feeding one normalized catalog**, then expose that catalog through Walker; do not copy the Quickshell surface.

## The integration surface: a Walker Actions menu

Omarchy's strongest reusable pattern is its data-driven command tree: a JSONC registry expresses nested actions, aliases, conditions, and providers, then groups capture, sharing, reminders, toggles, and style controls in one place ([registry model](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/default/omarchy/omarchy-menu.jsonc#L1-L12), [daily actions](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/default/omarchy/omarchy-menu.jsonc#L50-L89)).

This setup already has the right native host: Walker/Elephant enables the `menus` provider and already defines a custom GitHub menu with multiple actions ([current providers](https://github.com/thrawny/dotfiles/blob/6e00c1a853a1ec7eb09651cb8a72b9664e936913/nix/home/nixos/walker.nix#L22-L72), [custom-menu precedent](https://github.com/thrawny/dotfiles/blob/6e00c1a853a1ec7eb09651cb8a72b9664e936913/nix/home/nixos/walker.nix#L74-L88)). Add a small, curated `menus:actions` provider—preferably generated from a Nix attrset—with entries such as:

- Reminder: set/show/clear
- Capture: OCR/QR/color/record
- Share: Taildrop/LocalSend/file/folder/clipboard
- Network: share current Wi-Fi as QR
- Media: transcode, download current browser video
- Style: preview/apply theme, next background
- Device: external brightness and Moonlight

This gives the fun integrations a discoverable home without cloning Omarchy's shell. Keep direct keybindings only for high-frequency actions.

## Theming: adopt as a concrete track

The current Molokai family is coherent but represented independently in Niri, Waybar, Mako, Ghostty, Walker, Neovim, btop, Pi, and Codex ([Niri](https://github.com/thrawny/dotfiles/blob/6e00c1a853a1ec7eb09651cb8a72b9664e936913/nix/home/linux/niri/default.nix#L9-L16), [Waybar](https://github.com/thrawny/dotfiles/blob/6e00c1a853a1ec7eb09651cb8a72b9664e936913/nix/home/nixos/waybar.nix#L5-L25), [Ghostty](https://github.com/thrawny/dotfiles/blob/6e00c1a853a1ec7eb09651cb8a72b9664e936913/nix/home/shared/ghostty.nix#L3-L26), [Pi](https://github.com/thrawny/dotfiles/blob/6e00c1a853a1ec7eb09651cb8a72b9664e936913/config/pi/themes/monokai-pi.json#L1-L20)). Omarchy defines semantic colors once, renders consumer templates, and lets an explicit consumer file override a generated default ([theme flow](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/docs/theming.md#L3-L29), [semantic roles](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/docs/theming.md#L31-L91)). That model is worth adopting, but the source of truth should fit this repository.

### Proposed architecture

Use a versioned, application-neutral file such as `config/theme/monokai.toml`, not only a Nix attrset. Both the Nix-generated desktop and mutable out-of-store `config/nvim`/`config/pi` trees can consume or derive from it without losing immediate-edit behavior.

Start with these roles:

```toml
mode = "dark"
background = "#1c1c1c"
surface = "#262a31"
surface_strong = "#3a3a3a"
foreground = "#f0f0f0"
muted = "#75715e"
accent = "#f92672"
accent_alt = "#fd971f"
selection = "#49483e"
urgent = "#cc4444"
success = "#a6e22e"
warning = "#fd971f"
```

Then migrate in three deliberately boring passes:

1. **No-visual-change foundation.** Read the TOML during Nix evaluation and replace literals in Niri, Waybar, Walker, Mako, Ghostty, btop, and hyprlock with semantic lookups. Preserve intentional exceptions such as Neovim's different background instead of forcing uniformity.
2. **Mutable adapters.** Have small checked-in adapters derive Pi and Neovim roles from the same data. Keep Codex on its supported named theme unless a stable custom-theme interface exists. Add a `just check-theme` recipe that renders or validates adapters and fails on drift.
3. **Optional theme switching.** Only after one palette is clean, add additional palette files and a Walker preview/apply action. Omarchy's switcher caches image previews and its backgrounds are grouped by theme ([theme previews](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/bin/omarchy-theme-switcher#L12-L49), [background cycling](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/bin/omarchy-theme-bg-next#L6-L47)). Here, generate Home Manager outputs and reload the affected services; do not mutate application configs in place.

The first milestone is centralized semantics, not a gallery of themes. It removes current drift while keeping the visual identity the user already likes.

## Add soon: strong fits

### 1. Moonlight on the Z13

**Decision: adopt.** The desktop already runs Sunshine specifically for Moonlight streaming ([current Sunshine host](https://github.com/thrawny/dotfiles/blob/6e00c1a853a1ec7eb09651cb8a72b9664e936913/nix/hosts/desktop/default.nix#L75-L83), [gaming setup](https://github.com/thrawny/dotfiles/blob/6e00c1a853a1ec7eb09651cb8a72b9664e936913/nix/hosts/desktop/default.nix#L119-L152)), while the Z13 package list has no Moonlight client ([Z13 packages](https://github.com/thrawny/dotfiles/blob/6e00c1a853a1ec7eb09651cb8a72b9664e936913/nix/hosts/thrawny-z13/default.nix#L295-L304)). Omarchy installs `moonlight-qt` and makes its window fullscreen with fullscreen idle inhibition ([package](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/install/omarchy-base.packages#L76-L84), [window policy](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/default/hypr/apps/moonlight.lua#L1)).

Add `pkgs.moonlight-qt` only to the Z13 and a Niri rule that opens it fullscreen. Verify that Moonlight's own Wayland idle inhibitor is honored; if it is not, launch it through the existing caffeine mechanism rather than assuming Hyprland's rule maps directly. This completes an integration already half-built rather than adding a new platform. Test LAN first; Tailscale streaming can be a later experiment.

### 2. Taildrop actions

**Decision: adopt before LocalSend.** Tailscale is already enabled system-wide ([current service](https://github.com/thrawny/dotfiles/blob/6e00c1a853a1ec7eb09651cb8a72b9664e936913/nix/modules/nixos/system.nix#L163-L167)), but there is no peer/file workflow. Omarchy wraps `tailscale file cp` with a chooser and success/error notifications, and runs a receiver that stages deliveries, resolves filename conflicts safely, previews received images, and opens the file from the notification ([send](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/bin/omarchy-tailscale-send#L21-L49), [receive](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/bin/omarchy-tailscale-receive#L15-L99)).

Port the behavior as `tailscale-send` plus a Home Manager user service for receive. Populate Walker targets from `tailscale status --json`, rather than hard-coding peers. This is low-dependency and works away from the local LAN.

### 3. Lightweight reminders

**Decision: easy win.** Omarchy creates transient user timers with `systemd-run`, can enumerate or clear them, and stores only the optional message alongside the timer ([timer model](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/bin/omarchy-reminder#L23-L35), [creation](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/bin/omarchy-reminder#L168-L201)).

Port a smaller `remind <duration> [message]` command and Walker actions for set/list/clear. Use Mako for delivery; no permanent daemon or task app is needed.

### 4. Wi-Fi QR sharing

**Decision: easy win, especially on the Z13.** Omarchy finds the active NetworkManager Wi-Fi connection, rejects enterprise networks, escapes the standard Wi-Fi QR payload correctly, and includes WEP/open/hidden-network handling ([implementation](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/bin/omarchy-network-qr#L20-L88)).

Generate a temporary PNG with `qrencode`, show it in `imv`, and delete it when the viewer exits. Keep the password out of arguments, logs, and notifications. The existing NetworkManager setup means this is a very small addition.

### 5. Transcode-and-share

**Decision: adopt the command first, then the Nautilus action.** Omarchy converts images to stripped/resized JPEG or PNG, videos to MP4 or GIF at named sizes, then copies the output as a Wayland file URI ([formats and transforms](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/bin/omarchy-transcode#L22-L121), [clipboard handoff](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/bin/omarchy-transcode#L123-L129), [result flow](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/bin/omarchy-transcode#L163-L204)). Its Nautilus extension exposes the action only for supported media and handles multiple selections ([extension](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/default/nautilus-python/extensions/transcode.py#L11-L15), [menu behavior](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/default/nautilus-python/extensions/transcode.py#L18-L94)).

This fits the current Nautilus, mpv, imv, and `wl-clipboard` setup. Implement a deterministic CLI with a few practical presets, expose it in Walker, then add the right-click integration after the CLI proves useful.

### 6. LocalSend and Nautilus

**Decision: adopt if non-tailnet transfers are common.** Omarchy can send clipboard text, selected files, or folders through headless LocalSend, and adds a Nautilus context action that supports both a native package and Flatpak ([share wrapper](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/bin/omarchy-menu-share#L14-L48), [Nautilus action](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/default/nautilus-python/extensions/localsend.py#L11-L39), [selection menu](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/default/nautilus-python/extensions/localsend.py#L48-L84)).

Taildrop is the better first choice for this user's own machines because Tailscale already exists. LocalSend earns its place for phones, guests, and LAN-only devices. If the clipboard path is ported, clean the temporary file after the send process exits rather than relying on periodic `/tmp` cleanup.

### 7. Declarative Helium web apps

**Decision: adopt the idea, not the mutable installer.** Omarchy creates desktop launchers for arbitrary sites, fetches an icon, and launches supported Chromium browsers in app mode ([installer](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/bin/omarchy-webapp-install#L68-L99), [desktop entry](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/bin/omarchy-webapp-install#L131-L159), [app-mode launcher](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/bin/omarchy-launch-webapp#L6-L13)).

The current `niri-open-url` logic is excellent for routing ordinary links into the nearest Helium window, but it does not define standalone site apps ([current router](https://github.com/thrawny/dotfiles/blob/6e00c1a853a1ec7eb09651cb8a72b9664e936913/bin/niri-open-url#L103-L149)). Add a declarative `webApps` attrset that generates `.desktop` entries using `helium --app=<url>`, pinned/local icons, and optional Niri rules. Good candidates are frequently used single-purpose admin surfaces; do not turn every bookmark into an app.

## Trial selectively

### Browser-to-`yt-dlp`

**Decision: worthwhile experiment in Helium.** Omarchy ships a minimal Chromium extension with an `Alt+Shift+D` action and a native-messaging host; the host validates the page URL, downloads one video with `yt-dlp`, reports progress, makes a thumbnail, and offers to open the result in mpv ([extension manifest](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/default/chromium/extensions/yt-dlp/manifest.json#L1-L22), [native host](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/bin/omarchy-chromium-ytdlp-host#L18-L47), [download/result](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/bin/omarchy-chromium-ytdlp-host#L49-L110)).

This is more fluid than copying a URL into a terminal, but it adds a privileged browser/native boundary. Vendor and review the tiny extension, restrict the native manifest to its fixed extension ID, keep `--no-playlist`, and make the output directory explicit. First confirm Helium's extension policy supports a stable declarative install.

### Capture palette: OCR, QR, color, quick recording

**Decision: adopt OCR/QR/color; trial recording.** The current setup has excellent Niri screenshot bindings and the Z13 already has OBS ([capture bindings](https://github.com/thrawny/dotfiles/blob/6e00c1a853a1ec7eb09651cb8a72b9664e936913/nix/home/linux/niri/default.nix#L273-L304), [OBS on Z13](https://github.com/thrawny/dotfiles/blob/6e00c1a853a1ec7eb09651cb8a72b9664e936913/nix/hosts/thrawny-z13/default.nix#L295-L304)). Omarchy layers OCR, QR-only decoding, color picking, and recordings with optional desktop audio, microphone, and webcam onto one capture menu ([capture menu](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/default/omarchy/omarchy-menu.jsonc#L53-L64), [OCR](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/bin/omarchy-capture-text#L14-L26), [sensitive QR handling](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/bin/omarchy-capture-qr#L21-L36)).

Use one Niri-native region primitive for OCR and QR; retain `wl-copy --sensitive` for QR results. Color picking is another tiny Walker action. Only add a `gpu-screen-recorder` wrapper if quick clips are meaningfully faster than OBS: Omarchy's implementation handles region/fullscreen, combined audio, final trimming/normalization, and clickable thumbnail notifications, but contains Hyprland-specific target and webcam positioning ([record path](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/bin/omarchy-capture-screenrecording#L146-L202), [finalization](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/bin/omarchy-capture-screenrecording#L204-L279)).

### Audio-output cycle

**Decision: small optional win.** The current volume keys adjust the active sink and Pavucontrol handles manual routing, but there is no one-key output cycle ([current media bindings](https://github.com/thrawny/dotfiles/blob/6e00c1a853a1ec7eb09651cb8a72b9664e936913/nix/home/linux/niri/default.nix#L306-L339), [desktop audio packages](https://github.com/thrawny/dotfiles/blob/6e00c1a853a1ec7eb09651cb8a72b9664e936913/nix/modules/nixos/desktop.nix#L22-L36)). Omarchy cycles only available sinks, preserves the next sink's volume/mute state, and moves active application streams while leaving DSP plumbing alone ([sink selection](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/bin/omarchy-audio-output-switch#L5-L59), [stream migration](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/bin/omarchy-audio-output-set-default#L15-L30)).

Add it only if switching among dock/monitor speakers, headphones, and Bluetooth is frequent. A Walker action plus one media chord is enough; Pavucontrol remains the detailed control surface.

### Playful style extras

**Decision: optional after the palette work.** Omarchy offers cached theme/background image previews and can turn an SVG/PNG into terminal braille/block art for a randomized text-effect screensaver ([image-to-text](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/bin/omarchy-transcode-ascii#L1-L24), [branding flow](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/bin/omarchy-branding-screensaver#L11-L23), [effects](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/bin/omarchy-screensaver#L19-L48)).

The current `wpaperd` already rotates assets hourly ([current wallpaper service](https://github.com/thrawny/dotfiles/blob/6e00c1a853a1ec7eb09651cb8a72b9664e936913/nix/home/linux/niri/default.nix#L724-L731)). A Walker image preview for backgrounds or a branded `ttfx` launcher would be fun, but neither should complicate locking, idle, or multi-monitor behavior. Treat the screensaver as an explicit toy command, not a security surface.

## Retain from the Quattro-focused review

| Candidate | Decision | Why / next step |
| --- | --- | --- |
| Focused external-monitor DDC brightness | **Adopt** | Quattro maps a DRM connector to its DDC bus, caches lookups, normalizes VCP 0x10, and invalidates failures ([implementation](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/bin/omarchy-brightness-display-ddc#L12-L101)). Replace `hyprctl` with focused-workspace output from Niri, retain `brightnessctl` for eDP, and test every physical display. |
| mpv MPRIS | **Easy win** | `mpv` is installed and media keys already use `playerctl`, but no MPRIS script is configured ([current viewer](https://github.com/thrawny/dotfiles/blob/6e00c1a853a1ec7eb09651cb8a72b9664e936913/nix/home/nixos/viewers.nix#L11-L17), [keys](https://github.com/thrawny/dotfiles/blob/6e00c1a853a1ec7eb09651cb8a72b9664e936913/nix/home/linux/niri/default.nix#L357-L383)). Omarchy includes `mpv-mpris` beside mpv ([packages](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/install/omarchy-base.packages#L82-L86)); configure Home Manager's packaged mpv script. |
| Z13 zram beside hibernation swap | **Careful trial** | Omarchy gives zram priority over its disk hibernation swap ([config](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/default/systemd/zram-generator.conf.d/90-omarchy.conf#L1-L9)). Preserve the Z13's fixed resume device/swapfile and require real suspend plus hibernate/resume testing. The desktop already has intentional zram; do not change it in this work. |
| App scopes plus pressure-based oomd | **Later prototype** | Omarchy makes only `app.slice` a kill candidate and excludes the compositor ([scope](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/default/systemd/user/app.slice.d/10-oomd.conf#L1-L16)); its policy uses sustained PSI pressure ([oomd](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/etc/systemd/oomd.conf.d/10-omarchy.conf#L1-L21)). Prove app placement and compositor exclusion before comparing it with current `earlyoom`. |
| Crash notification and agent diagnosis | **Opt-in later** | Omarchy filters structured coredump journal records to the current UID, deduplicates loops, and offers agent diagnosis ([watcher](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/bin/omarchy-crash-watch#L1-L84), [handoff](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/bin/omarchy-agent-crash#L1-L48)). Route it through existing agent-switch tooling and never upload cores automatically. |
| Event-driven agent status | **Small cleanup** | Current Waybar agent status polls every two seconds while caffeine already uses a one-shot/signal pattern ([modules](https://github.com/thrawny/dotfiles/blob/6e00c1a853a1ec7eb09651cb8a72b9664e936913/nix/home/nixos/waybar.nix#L284-L311)). Signal Waybar from agent-switch state changes and retain a slow fallback refresh. |

## Existing overlap: do not rebuild

- **Voice input:** Wayvoice already has toggle/cancel bindings and resume-specific hardware work ([bindings](https://github.com/thrawny/dotfiles/blob/6e00c1a853a1ec7eb09651cb8a72b9664e936913/nix/home/linux/niri/default.nix#L273-L296)); Omarchy's Voxtype flow is not additive.
- **Launcher, clipboard, emoji/symbols, files, windows, and Niri actions:** Walker already enables those providers ([providers](https://github.com/thrawny/dotfiles/blob/6e00c1a853a1ec7eb09651cb8a72b9664e936913/nix/home/nixos/walker.nix#L60-L72)). Add the Actions menu; do not replace the launcher.
- **Agent selection and quota status:** Waybar and agent-switch are already more developed than Omarchy's default-agent abstraction ([Waybar modules](https://github.com/thrawny/dotfiles/blob/6e00c1a853a1ec7eb09651cb8a72b9664e936913/nix/home/nixos/waybar.nix#L284-L303)).
- **Networking, Bluetooth, audio UI, removable locations:** NetworkManager, Blueman, PipeWire/Pavucontrol, and GVfs/Nautilus are present ([desktop services](https://github.com/thrawny/dotfiles/blob/6e00c1a853a1ec7eb09651cb8a72b9664e936913/nix/modules/nixos/desktop.nix#L104-L135)). Add task-specific QR/transfer actions, not a replacement control center.
- **Gaming host stack:** Steam, GameMode, Gamescope, and Sunshine are already configured on the desktop ([gaming config](https://github.com/thrawny/dotfiles/blob/6e00c1a853a1ec7eb09651cb8a72b9664e936913/nix/hosts/desktop/default.nix#L119-L152)). Moonlight on the Z13 is the missing complementary piece; Omarchy's broader gaming bundle is not.
- **Fingerprint, idle, and clamshell behavior:** preserve the current fingerprint lock, custom idle policy, and debounced Z13 lid/output synchronization ([lock](https://github.com/thrawny/dotfiles/blob/6e00c1a853a1ec7eb09651cb8a72b9664e936913/nix/home/linux/hyprlock.nix#L20-L35), [idle](https://github.com/thrawny/dotfiles/blob/6e00c1a853a1ec7eb09651cb8a72b9664e936913/nix/home/nixos/hypridle.nix#L1-L47), [clamshell](https://github.com/thrawny/dotfiles/blob/6e00c1a853a1ec7eb09651cb8a72b9664e936913/nix/hosts/thrawny-z13/default.nix#L219-L245)).

## What not to adopt

### The full Quickshell desktop

Quattro replaces Waybar, Walker, Mako, SwayOSD, hyprlock, hypridle, swaybg, and polkit-gnome with one shell process ([release overview](https://github.com/basecamp/omarchy/releases/tag/v4.0.0#the-quattro-release)). Its runtime layout includes Hyprland panels, monitor handling, geometry, bindings, and services ([shell layout](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/shell/README.md#L1-L42)). The current setup is deeply Niri-native; a port would be a new desktop project, not a component swap.

### Mutable, unsandboxed shell plugins

Omarchy installs plugin repositories into user config and executes enabled plugins with the user's authority; its documentation explicitly warns about this trust model ([warning and update flow](https://github.com/basecamp/omarchy/blob/f0020448ca87329199de7cb12f2015ebc4a3e5e7/shell/README.md#L94-L125)). That conflicts with reviewed, pinned, declarative Nix inputs. Port a compelling behavior as a small reviewed command or Walker provider instead.

### Arch/Hyprland/install-appliance machinery

Skip the Lua Hyprland config, pacman/ALPM guard, Arch package layout, dual-boot/OEM provisioning, factory reset, Foot default, mutable app installers, and bulk app bundle. Likewise, keep the existing TLP laptop policy rather than adding another power-profile controller ([current laptop policy](https://github.com/thrawny/dotfiles/blob/6e00c1a853a1ec7eb09651cb8a72b9664e936913/nix/modules/nixos/laptop.nix#L6-L27)).

## Suggested implementation batches

1. **Visual foundation:** canonical palette, Nix adapters, drift check; no visual changes.
2. **Niri action surface:** `menus:actions` with placeholder entries and stable categories.
3. **Immediate fun:** Moonlight on Z13, reminders, Wi-Fi QR, OCR/QR/color capture, mpv MPRIS, and optional audio-output cycling.
4. **Move things around:** Taildrop, then LocalSend if its wider device reach is useful.
5. **Media:** transcode/share command and Nautilus action; then optional quick recording.
6. **Browser:** declarative Helium web apps; separately trial the reviewed `yt-dlp` native action.
7. **Hardware and resilience:** DDC brightness, Z13 zram test, app-scope/oomd experiment, opt-in crash watcher.
