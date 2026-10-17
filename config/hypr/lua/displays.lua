-- Native display profiles: connector names can change when the dock reconnects.
local lg_description = "LG Electronics 27GL850"
local aoc_description = "AOC Q27G2WG4"

hl.monitor({
	output = "desc:" .. lg_description,
	mode = "2560x1440@99.95",
	position = "0x0",
	scale = 1,
})
hl.monitor({
	output = "desc:" .. aoc_description,
	mode = "2560x1440@143.91",
	position = "2560x0",
	scale = 1,
})

-- Read the Z13's initial state too: switch binds alone miss a closed-lid login.
local lid_closed = false
local lid = io.open("/proc/acpi/button/lid/LID/state", "r")
if lid then
	lid_closed = lid:read("*a"):find("closed", 1, true) ~= nil
	lid:close()
end

local panel_disabled
local workspace_targets = {}

local function sync_displays()
	local lg, aoc, external
	for _, monitor in ipairs(hl.get_monitors()) do
		if not monitor.name:match("^eDP%-") and not monitor.name:match("^LVDS%-") then
			external = external or monitor.name
		end
		if monitor.description:sub(1, #lg_description) == lg_description then
			lg = monitor.name
		elseif monitor.description:sub(1, #aoc_description) == aoc_description then
			aoc = monitor.name
		end
	end

	-- At home the panel stays off even with the lid open. At other docks it
	-- participates while open. Never disable the last display on lid close.
	local disable = lg ~= nil or aoc ~= nil or (lid_closed and external ~= nil)
	if panel_disabled ~= disable then
		panel_disabled = disable
		-- 2880px / (5/3) = 1728 logical pixels: panel sits left of the LG
		-- when manually enabled at home, with the top edges aligned.
		hl.monitor({
			output = "eDP-1",
			disabled = disable,
			position = (lg or aoc) and "-1728x0" or "auto",
			scale = 5 / 3,
		})
	end

	local panel = hl.get_monitor("eDP-1")
	if panel and not disable then
		-- Logind ignores lid events. With no external display, only blank the
		-- panel; disabling the last output would leave a headless compositor.
		hl.dispatch(hl.dsp.dpms({ action = lid_closed and "off" or "on", monitor = "eDP-1" }))
	end

	local primary = lg or aoc or external or (panel and panel.name)
	if not primary then
		return
	end
	local targets = { primary, aoc or primary, primary }
	local names = { "main", "web", "dotfiles" }
	for id, target in ipairs(targets) do
		if workspace_targets[id] ~= target then
			workspace_targets[id] = target
			hl.workspace_rule({
				workspace = tostring(id),
				default_name = names[id],
				persistent = true,
				monitor = target,
			})
			-- Rules place future workspaces; move existing ones on dock changes.
			local workspace = hl.get_workspace(tostring(id))
			if workspace and workspace.monitor and workspace.monitor.name ~= target then
				hl.dispatch(hl.dsp.workspace.move({ workspace = tostring(id), monitor = target }))
			end
		end
	end
end

-- Install rules while the config is loading, before Hyprland reapplies monitor
-- and persistent-workspace rules. Waiting for the timer briefly enables the
-- panel and moves web off the AOC, leaving a new empty workspace behind.
sync_displays()

-- Coalesce dock enumeration and lid-sensor bounce. Reuse a parked repeat timer:
-- Hyprland destroys oneshot timers after firing, so they cannot be re-enabled.
local settle_timer
settle_timer = hl.timer(function()
	settle_timer:set_enabled(false)
	sync_displays()
end, { timeout = 500, type = "repeat" })

local function schedule_sync()
	settle_timer:set_enabled(true)
end

hl.on("monitor.added", schedule_sync)
hl.on("monitor.removed", schedule_sync)
hl.on("config.reloaded", schedule_sync)
hl.on("hyprland.start", schedule_sync)

local switch_options = {
	locked = true,
	ignore_mods = true,
	submap_universal = true,
	dont_inhibit = true,
}
hl.bind("switch:on:Lid Switch", function()
	lid_closed = true
	-- Closing the lid must disable the panel even after a manual enable.
	panel_disabled = nil
	schedule_sync()
end, switch_options)
hl.bind("switch:off:Lid Switch", function()
	lid_closed = false
	schedule_sync()
end, switch_options)
