-- Alt-a app-jump submap, the native counterpart of the xremap/nirius chords
-- used under niri (the Hyprland xremap variant omits them; see
-- nix/home/nixos/xremap.nix). Any bound key jumps and exits the submap
-- (auto-reset); any other key just exits via catchall.

local dsp = hl.dsp

-- Focus the first window whose class or title contains the matcher
-- (case-insensitive, plain substring); optionally spawn when nothing matches.
local function jump(matcher, spawn_cmd)
	return function()
		local pattern = matcher:lower()
		for _, w in ipairs(hl.get_windows()) do
			local class = (w.class or ""):lower()
			local title = (w.title or ""):lower()
			if class:find(pattern, 1, true) or title:find(pattern, 1, true) then
				hl.dispatch(dsp.focus({ window = w }))
				return
			end
		end
		if spawn_cmd then
			hl.dispatch(dsp.exec_cmd(spawn_cmd))
		end
	end
end

hl.bind("ALT + A", dsp.submap("appjump"))

hl.define_submap("appjump", "reset", function()
	hl.bind("A", jump("k9s"))
	hl.bind("S", jump("slack"))
	hl.bind("D", jump("microsoft teams"))
	hl.bind("B", jump("btop++", "ghostty --title=btop++ -e btop"))
	hl.bind("Z", jump("discord"))
	hl.bind("T", jump("org.telegram.desktop"))
	hl.bind("catchall", dsp.submap("reset"))
end)
