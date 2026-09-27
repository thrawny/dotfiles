-- Logind ignores lid events. Keep the internal panel's DPMS state in sync;
-- otherwise the Z13 can reopen black while Hyprland still considers it on.
local function panel_power(action)
	-- A missing monitor selector falls back to all monitors in Hyprland 0.56.
	-- Never touch external displays on machines without this laptop panel.
	if hl.get_monitor("eDP-1") then
		hl.dispatch(hl.dsp.dpms({ action = action, monitor = "eDP-1" }))
	end
end

-- Park a reusable timer between events. Hyprland destroys oneshot timers after
-- firing, so a repeat timer that disables itself can handle later lid cycles.
local open_timer
open_timer = hl.timer(function()
	open_timer:set_enabled(false)
	panel_power("on")
end, { timeout = 500, type = "repeat" })
open_timer:set_enabled(false)

local switch_options = {
	locked = true,
	ignore_mods = true,
	submap_universal = true,
	dont_inhibit = true,
}

hl.bind("switch:on:Lid Switch", function()
	-- Cancel any pending wake from an earlier lid-open bounce.
	open_timer:set_enabled(false)
	panel_power("off")
end, switch_options)

hl.bind("switch:off:Lid Switch", function()
	-- Let the physical lid settle before enabling the panel. Repeated open
	-- events restart the delay rather than scheduling overlapping commands.
	open_timer:set_enabled(true)
end, switch_options)
