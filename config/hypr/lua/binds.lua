-- Keybinds, ported from the niri config (Alt is the main mod there too).
-- Scrolling-layout commands go through hl.dsp.layout("..."); see
-- https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/

local bind = hl.bind
local dsp = hl.dsp

-- Toggle a special-workspace scratchpad, spawning the app first if it isn't
-- running. The pgrep guard runs in the shell so no compositor state is needed.
local function scratchpad(special, spawn_guard)
	return function()
		hl.dispatch(dsp.exec_cmd(spawn_guard))
		hl.dispatch(dsp.workspace.toggle_special(special))
	end
end

-- Launchers
bind("ALT + Return", dsp.exec_cmd("ghostty"))
bind("SUPER + Space", dsp.exec_cmd("walker"))
bind("ALT + Q", scratchpad("term", "pgrep -f GhosttyScratchpad || ghostty --class=com.thrawny.GhosttyScratchpad"))
bind("ALT + O", scratchpad("1password", "pgrep -x 1password || 1password"))
bind("ALT + P", scratchpad("spotify", "pgrep -x spotify || spotify"))

-- Session
bind("ALT + Escape", dsp.exec_cmd("hyprlock"))
bind("ALT + SHIFT + Escape", dsp.exit())
bind("ALT + SHIFT + CTRL + Delete", dsp.exec_cmd("systemctl poweroff"))
bind("CTRL + ALT + Delete", dsp.exec_cmd("reboot"))
bind("ALT + SHIFT + P", dsp.dpms({ action = "off" }))
bind("ALT + SUPER + M", dsp.exec_cmd("wake-lg"), { locked = true })
bind("ALT + SUPER + E", dsp.dpms({ action = "on", monitor = "eDP-1" }), { locked = true })
bind("ALT + SUPER + Space", dsp.exec_cmd("hyprctl switchxkblayout all next"))

-- Windows
bind("ALT + W", dsp.window.close())
bind("ALT + F", dsp.window.fullscreen({ mode = "maximized", layout_aware = true }))
bind("ALT + SHIFT + F", dsp.window.fullscreen({ mode = "fullscreen", layout_aware = true }))
bind("ALT + V", dsp.window.float({ action = "toggle" }))
bind("ALT + M", dsp.focus({ last = true }))
bind("ALT + Tab", dsp.focus({ last = true }))
bind("ALT + G", dsp.group.toggle())
bind("ALT + SHIFT + G", dsp.group.next())

-- Focus
bind("ALT + H", dsp.focus({ direction = "l" }))
bind("ALT + J", dsp.focus({ direction = "d" }))
bind("ALT + K", dsp.focus({ direction = "u" }))
bind("ALT + L", dsp.focus({ direction = "r" }))

-- Move columns/windows
bind("ALT + SHIFT + H", dsp.layout("swapcol l"))
bind("ALT + SHIFT + L", dsp.layout("swapcol r"))
bind("ALT + SHIFT + J", dsp.window.swap({ direction = "d" }))
bind("ALT + SHIFT + K", dsp.window.swap({ direction = "u" }))

-- Scrolling layout: columns
bind("ALT + bracketleft", dsp.layout("consume"))
bind("ALT + bracketright", dsp.layout("expel"))
bind("ALT + backslash", dsp.layout("colresize +conf"))
bind("ALT + minus", dsp.layout("colresize -0.1"))
bind("ALT + equal", dsp.layout("colresize +0.1"))
bind("ALT + C", dsp.layout("fit_into_view"))
bind("ALT + CTRL + F", dsp.layout("fit active"))
bind("ALT + CTRL + C", dsp.layout("fit visible"))

-- Workspaces (1-3 are named: main, web, dotfiles — see rules.lua)
bind("ALT + B", dsp.focus({ workspace = "name:web" }))
bind("ALT + U", dsp.focus({ workspace = "e-1" }))
bind("ALT + I", dsp.focus({ workspace = "e+1" }))
bind("ALT + CTRL + U", dsp.window.move({ workspace = "e-1", follow = true }))
bind("ALT + CTRL + I", dsp.window.move({ workspace = "e+1", follow = true }))

for i = 1, 9 do
	bind("ALT + " .. i, dsp.focus({ workspace = tostring(i) }))
	bind("ALT + SHIFT + " .. i, dsp.window.move({ workspace = tostring(i), follow = true }))
end
bind("ALT + 0", dsp.focus({ workspace = "10" }))
bind("ALT + SHIFT + 0", dsp.window.move({ workspace = "10", follow = true }))

-- Monitors
bind("ALT + N", dsp.focus({ monitor = "-1" }))
bind("ALT + CTRL + H", dsp.focus({ monitor = "l" }))
bind("ALT + CTRL + J", dsp.focus({ monitor = "d" }))
bind("ALT + CTRL + K", dsp.focus({ monitor = "u" }))
bind("ALT + CTRL + L", dsp.focus({ monitor = "r" }))
bind("ALT + SHIFT + CTRL + H", dsp.window.move({ monitor = "l", follow = true }))
bind("ALT + SHIFT + CTRL + J", dsp.window.move({ monitor = "d", follow = true }))
bind("ALT + SHIFT + CTRL + K", dsp.window.move({ monitor = "u", follow = true }))
bind("ALT + SHIFT + CTRL + L", dsp.window.move({ monitor = "r", follow = true }))
bind("ALT + SUPER + H", dsp.workspace.move({ monitor = "l" }))
bind("ALT + SUPER + J", dsp.workspace.move({ monitor = "d" }))
bind("ALT + SUPER + K", dsp.workspace.move({ monitor = "u" }))
bind("ALT + SUPER + L", dsp.workspace.move({ monitor = "r" }))

-- Mouse
bind("ALT + mouse:272", dsp.window.drag(), { mouse = true })
bind("ALT + mouse:273", dsp.window.resize(), { mouse = true })
bind("ALT + mouse_down", dsp.focus({ workspace = "e+1" }))
bind("ALT + mouse_up", dsp.focus({ workspace = "e-1" }))

-- Voice input
bind("ALT + R", dsp.exec_cmd("wayvoice toggle"))
bind("ALT + SHIFT + R", dsp.exec_cmd("wayvoice cancel"))
bind("SUPER + SHIFT + P", dsp.exec_cmd("wayvoice cancel"))

-- Screenshots (hyprshot; output dir comes from HYPRSHOT_DIR in options.lua)
bind("Print", dsp.exec_cmd("hyprshot -m region"))
bind("CTRL + Print", dsp.exec_cmd("hyprshot -m output"))
bind("ALT + Print", dsp.exec_cmd("hyprshot -m window"))
bind("SUPER + SHIFT + 3", dsp.exec_cmd("hyprshot -m output"))
bind("SUPER + SHIFT + 4", dsp.exec_cmd("hyprshot -m region"))
bind("SUPER + SHIFT + 5", dsp.exec_cmd("hyprshot -m window"))

-- Volume / brightness / media (swayosd, same as niri)
bind("XF86AudioRaiseVolume", dsp.exec_cmd("swayosd-client --output-volume raise"), {
	locked = true,
	repeating = true,
})
bind("XF86AudioLowerVolume", dsp.exec_cmd("swayosd-client --output-volume lower"), {
	locked = true,
	repeating = true,
})
bind("XF86AudioMute", dsp.exec_cmd("swayosd-client --output-volume mute-toggle"), { locked = true })
bind("XF86AudioMicMute", dsp.exec_cmd("swayosd-client --input-volume mute-toggle"), { locked = true })
bind("XF86MonBrightnessUp", dsp.exec_cmd("swayosd-client --brightness raise"), {
	locked = true,
	repeating = true,
})
bind("XF86MonBrightnessDown", dsp.exec_cmd("swayosd-client --brightness lower"), {
	locked = true,
	repeating = true,
})
bind("XF86AudioPlay", dsp.exec_cmd("playerctl play-pause"), { locked = true })
bind("XF86AudioPause", dsp.exec_cmd("playerctl play-pause"), { locked = true })
bind("XF86AudioNext", dsp.exec_cmd("playerctl next"), { locked = true })
bind("XF86AudioPrev", dsp.exec_cmd("playerctl previous"), { locked = true })
