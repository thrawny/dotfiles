-- Session autostart (exec-once equivalent). wpaperd is a systemd user service
-- and starts on its own (via uwsm's graphical-session.target).

local home = os.getenv("HOME")

hl.on("hyprland.start", function()
	-- Headless session daemon; the GTK overlay (serve --niri) is niri-only.
	hl.exec_cmd("agent-switch serve")
	hl.exec_cmd("swayosd-server")
	hl.exec_cmd("wl-paste --watch cliphist store")
	hl.exec_cmd("mako")
	-- The launcher keeps Waybar as a fallback if the custom bar fails to load.
	hl.exec_cmd("dotfiles-bar")

	hl.dispatch(hl.dsp.exec_cmd("ghostty +new-window --working-directory=" .. home .. "/dotfiles", {
		workspace = "3",
	}))
	hl.dispatch(hl.dsp.exec_cmd("helium --profile-directory=Default", { workspace = "2" }))
end)
