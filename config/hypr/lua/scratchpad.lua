-- Wait for a newly spawned window before showing its special workspace.
return function(special, spawn_guard, matches)
	local pending = false
	hl.on("window.open", function(window)
		if not pending or not matches(window) then
			return
		end
		pending = false
		local active = hl.get_active_special_workspace()
		if not active or active.name ~= "special:" .. special then
			hl.dispatch(hl.dsp.workspace.toggle_special(special))
		end
	end)
	return function()
		for _, window in ipairs(hl.get_windows()) do
			if matches(window) then
				pending = false
				hl.dispatch(hl.dsp.workspace.toggle_special(special))
				return
			end
		end
		pending = true
		-- The process guard prevents duplicate launches while the window maps.
		hl.dispatch(hl.dsp.exec_cmd(spawn_guard))
	end
end
