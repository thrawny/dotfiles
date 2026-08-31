-- Session autostart (exec-once equivalent). wpaperd is a systemd user service
-- and starts on its own; agent-switch is niri-only for now (Lua port pending).

local home = os.getenv("HOME")

hl.on("hyprland.start", function()
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
