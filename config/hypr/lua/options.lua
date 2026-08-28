-- Look, input, and layout options. Mirrors the niri setup where possible:
-- Molokai borders, 8px gaps, rounded corners, flat mouse profile, au/se layout.

local home = os.getenv("HOME")

hl.env("XCURSOR_SIZE", "16")
hl.env("HYPRCURSOR_SIZE", "16")
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "wayland")
hl.env("NIXOS_OZONE_WL", "1")
hl.env("EDITOR", "nvim")
hl.env("HYPRSHOT_DIR", home .. "/Screenshots")

-- Auto-detect resolution/position/scale for any monitor; override per host in host.lua.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

hl.config({
	general = {
		layout = "scrolling",
		gaps_in = 4,
		gaps_out = 8,
		border_size = 2,
		["col.active_border"] = "rgba(f92672ee)",
		["col.inactive_border"] = "rgba(3a3a3aaa)",
		resize_on_border = false,
		allow_tearing = false,
	},

	scrolling = {
		column_width = 0.5,
		explicit_column_widths = "0.333, 0.5, 0.667, 1.0",
		-- A lone window keeps its column width instead of spanning the screen (niri behavior).
		fullscreen_on_one_column = false,
		focus_fit_method = 1,
		follow_focus = true,
	},

	decoration = {
		rounding = 12,
		inactive_opacity = 0.9,
		shadow = {
			enabled = true,
			range = 15,
			render_power = 3,
			color = "rgba(00000077)",
		},
		blur = {
			enabled = true,
			size = 5,
			passes = 2,
		},
	},

	-- Defaults are fine to start with; tune per-animation later if needed.
	animations = {
		enabled = true,
	},

	input = {
		kb_layout = "au,se",
		kb_options = "caps:escape",
		numlock_by_default = true,
		repeat_rate = 30,
		repeat_delay = 200,
		follow_mouse = 1,
		sensitivity = 0,
		accel_profile = "flat",
		touchpad = {
			natural_scroll = true,
			scroll_factor = 0.3,
			tap_to_click = true,
			clickfinger_behavior = true,
			disable_while_typing = false,
		},
	},

	misc = {
		disable_hyprland_logo = true,
		disable_splash_rendering = true,
		focus_on_activate = true,
	},

	xwayland = {
		force_zero_scaling = true,
	},

	ecosystem = {
		no_update_news = true,
	},
})
