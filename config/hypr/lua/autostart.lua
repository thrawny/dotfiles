-- Session autostart (exec-once equivalent). wpaperd is a systemd user service
-- and starts on its own (via uwsm's graphical-session.target).

local home = os.getenv("HOME")

hl.on("hyprland.start", function()
	-- Systemd owns the headless tracker across Quickshell reloads.
	hl.exec_cmd("systemctl --user start dotfiles-agent-switch.service")
	hl.exec_cmd("swayosd-server")
	hl.exec_cmd("mako")
	hl.exec_cmd("systemctl --user start dotfiles-shell.service shell-clipboard-text.service")

	hl.dispatch(hl.dsp.exec_cmd("ghostty +new-window --working-directory=" .. home .. "/dotfiles", {
		workspace = "3",
	}))
	hl.dispatch(hl.dsp.exec_cmd("helium --profile-directory=Default", { workspace = "2" }))
end)
