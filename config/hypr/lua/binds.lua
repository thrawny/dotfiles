-- Keybinds, ported from the niri config (Alt is the main mod there too).
-- Scrolling-layout commands go through hl.dsp.layout("..."); see
-- https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/

local bind = hl.bind
local dsp = hl.dsp

-- Toggle a special-workspace scratchpad, spawning the app first if it isn't
-- running. The pgrep guard runs in the shell so no compositor state is needed.
local function scratchpad(special, spawn_guard, window_class)
	local pending = false
	if window_class then
		hl.on("window.open", function(window)
			if not pending or window.class ~= window_class then
				return
			end
			pending = false
			local active = hl.get_active_special_workspace()
			if not active or active.name ~= "special:" .. special then
				hl.dispatch(dsp.workspace.toggle_special(special))
			end
		end)
	end
	return function()
		if window_class then
			local found = false
			for _, window in ipairs(hl.get_windows()) do
				if window.class == window_class then
					found = true
					break
				end
			end
			if not found then
				-- Opening an empty special workspace races the asynchronous spawn.
				-- The process guard also prevents duplicates during startup.
				pending = true
				hl.dispatch(dsp.exec_cmd(spawn_guard))
				return
			end
		end
		pending = false
		hl.dispatch(dsp.exec_cmd(spawn_guard))
		hl.dispatch(dsp.workspace.toggle_special(special))
	end
end

-- Launchers
-- Terminal opens in the workspace's project directory when one is
-- registered (project_dir from projectdirs.lua, set by hyprland-project).
bind("ALT + Return", function()
	local dir = project_dir()
	if dir then
		hl.dispatch(dsp.exec_cmd("ghostty +new-window --working-directory=" .. dir))
	else
		hl.dispatch(dsp.exec_cmd("ghostty"))
	end
end)
bind("SUPER + Space", dsp.exec_cmd("quickshell ipc -c dotfiles call launcher toggle"))
bind("ALT + S", dsp.exec_cmd("quickshell ipc -c dotfiles call agents toggle"))
bind("ALT + SHIFT + Space", dsp.exec_cmd("ghostty --title=project-picker -e project-picker --hypr"))
-- Anchor to the executable so pgrep cannot match the launcher shell itself.
bind(
	"ALT + Q",
	scratchpad(
		"term",
		"pgrep -f '^[^ ]*ghostty[^ ]* .*GhosttyScratchpad' || ghostty --class=com.thrawny.GhosttyScratchpad",
		"com.thrawny.GhosttyScratchpad"
	)
)
bind("ALT + O", scratchpad("1password", "pgrep -x 1password || 1password"))
bind("ALT + P", scratchpad("spotify", "pgrep -f '^[^ ]*/[.]spotify-wrapped( |$)' || pgrep -x spotify || spotify"))

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
bind("ALT + SHIFT + W", dsp.exec_cmd("hyprland-close-workspace"))
bind("ALT + F", dsp.window.fullscreen({ mode = "maximized", layout_aware = true }))
bind("ALT + SHIFT + F", dsp.window.fullscreen({ mode = "fullscreen", layout_aware = true }))
bind("ALT + V", dsp.window.float({ action = "toggle" }))
bind("ALT + M", dsp.focus({ last = true }))
bind("ALT + SHIFT + M", dsp.focus({ workspace = "previous" }))
bind("ALT + Tab", dsp.focus({ last = true }))
bind("ALT + G", dsp.group.toggle())
bind("ALT + SHIFT + G", dsp.group.next())

-- Switch only the active workspace between the niri-like scrolling layout and
-- Hyprland's standard dwindle layout. This follows Omarchy's SUPER+L toggle.
bind("SUPER + L", function()
	local workspace = hl.get_active_workspace()
	if not workspace then
		return
	end

	local layout = workspace.tiled_layout == "scrolling" and "dwindle" or "scrolling"
	hl.workspace_rule({ workspace = tostring(workspace.id), layout = layout })
	hl.notification.create({
		text = "Workspace layout: " .. layout,
		duration = 2000,
		icon = "info",
	})
end)

-- Generic directional focus can select another column at the tape's edge.
-- Scrolling's own focus command respects scrolling.wrap_focus = false.
local function focus_horizontal(direction)
	return function()
		local workspace = hl.get_active_workspace()
		local window = hl.get_active_window()
		if workspace and workspace.tiled_layout == "scrolling" and window and not window.floating then
			hl.dispatch(dsp.layout("focus " .. direction))
		else
			hl.dispatch(dsp.focus({ direction = direction }))
		end
	end
end

-- No first/last-column dispatcher exists. With wrap_focus disabled, walking
-- once per window reaches the edge without crossing into another workspace.
local function focus_edge(direction)
	return function()
		local workspace = hl.get_active_workspace()
		local window = hl.get_active_window()
		if not workspace or workspace.tiled_layout ~= "scrolling" or not window or window.floating then
			return
		end
		for _ = 1, #hl.get_windows() do
			hl.dispatch(dsp.layout("focus " .. direction))
		end
	end
end

-- Focus
bind("ALT + comma", focus_edge("l"))
bind("ALT + period", focus_edge("r"))
bind("ALT + H", focus_horizontal("l"))
bind("ALT + J", dsp.focus({ direction = "d" }))
bind("ALT + K", dsp.focus({ direction = "u" }))
bind("ALT + L", focus_horizontal("r"))

-- Move columns/windows
bind("ALT + SHIFT + H", dsp.layout("swapcol l"))
bind("ALT + SHIFT + L", dsp.layout("swapcol r"))
bind("ALT + SHIFT + J", dsp.window.swap({ direction = "d" }))
bind("ALT + SHIFT + K", dsp.window.swap({ direction = "u" }))

-- Scrolling layout: columns
bind("ALT + bracketleft", dsp.layout("consume_or_expel prev"))
bind("ALT + bracketright", dsp.layout("consume_or_expel next"))
bind("ALT + SHIFT + period", dsp.layout("expel"))
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

-- Number keys address the current workspace order, not persistent IDs.
-- Resolve on each keypress so closing a workspace immediately removes its gap.
local function workspace_at(index, move_window)
	return function()
		local workspaces = {}
		for _, ws in ipairs(hl.get_workspaces()) do
			if not ws.name:match("^special:") then
				table.insert(workspaces, ws)
			end
		end
		table.sort(workspaces, function(a, b)
			return a.id < b.id
		end)
		local target = workspaces[index]
		if not target then
			return
		end
		if move_window then
			hl.dispatch(dsp.window.move({ workspace = tostring(target.id), follow = true }))
		else
			hl.dispatch(dsp.focus({ workspace = tostring(target.id) }))
		end
	end
end

for i = 1, 10 do
	local key = tostring(i % 10)
	bind("ALT + " .. key, workspace_at(i, false))
	bind("ALT + SHIFT + " .. key, workspace_at(i, true))
end

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

-- Voice input is handled by xremap (evdev-level, compositor-agnostic).

-- Screenshots (hyprshot; output dir comes from HYPRSHOT_DIR in options.lua)
bind("Print", dsp.exec_cmd("hyprshot -m region --freeze"))
bind("CTRL + Print", dsp.exec_cmd("hyprshot -m output --freeze"))
bind("ALT + Print", dsp.exec_cmd("hyprshot -m window --freeze"))
bind("SUPER + SHIFT + 3", dsp.exec_cmd("hyprshot -m output --freeze"))
bind("SUPER + SHIFT + 4", dsp.exec_cmd("hyprshot -m region --freeze"))
bind("SUPER + SHIFT + 5", dsp.exec_cmd("hyprshot -m window --freeze"))

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
