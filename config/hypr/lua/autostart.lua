-- Session autostart (exec-once equivalent). wpaperd is a systemd user service
-- and starts on its own (via uwsm's graphical-session.target).

local home = os.getenv("HOME")

hl.on("hyprland.start", function()
	-- Headless session daemon; the GTK overlay (serve --niri) is niri-only.
	hl.exec_cmd("agent-switch serve")
	hl.exec_cmd("swayosd-server")
	hl.exec_cmd("wl-paste --watch cliphist store")
	hl.exec_cmd("mako")
	hl.exec_cmd(
		"waybar -c " .. home .. "/.config/waybar/config-hyprland -s " .. home .. "/.config/waybar/style-hyprland.css"
	)

	hl.dispatch(hl.dsp.exec_cmd("ghostty +new-window --working-directory=" .. home .. "/dotfiles", {
		workspace = "3",
	}))
	hl.dispatch(hl.dsp.exec_cmd("helium --profile-directory=Default", { workspace = "2" }))
end)
