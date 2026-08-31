-- Workspace and window rules, ported from the niri config.

-- Named workspaces matching niri's main/web/dotfiles.
hl.workspace_rule({ workspace = "1", default_name = "main", persistent = true })
hl.workspace_rule({ workspace = "2", default_name = "web", persistent = true })
hl.workspace_rule({ workspace = "3", default_name = "dotfiles", persistent = true })

-- Chat apps live on main.
hl.window_rule({
	name = "chat-on-main",
	match = { class = "^(org\\.telegram\\.desktop|Slack|teams-for-linux|vesktop|discord)$" },
	workspace = "name:main",
})

-- Floating control panels.
hl.window_rule({
	name = "float-control-panels",
	match = {
		class = "^(org\\.pulseaudio\\.pavucontrol|\\.blueman-manager-wrapped|blueman-manager|nm-connection-editor|xdg-desktop-portal.*)$",
	},
	float = true,
})
hl.window_rule({
	name = "pavucontrol-size",
	match = { class = "^org\\.pulseaudio\\.pavucontrol$" },
	size = { 1000, 700 },
})
hl.window_rule({
	name = "float-slack-huddle",
	match = { class = "^Slack$", title = "^(Slack - Huddle Preview|Huddle:)" },
	float = true,
})
hl.window_rule({
	name = "float-btop",
	match = { title = "^btop\\+\\+$" },
	float = true,
})
hl.window_rule({
	name = "float-project-picker",
	match = { title = "^project-picker$" },
	float = true,
})

-- Scratchpads on special workspaces (toggled from binds.lua).
hl.window_rule({
	name = "scratchpad-terminal",
	match = { class = "^com\\.thrawny\\.GhosttyScratchpad$" },
	workspace = "special:term",
	float = true,
	size = { 1400, 900 },
})
hl.window_rule({
	name = "scratchpad-1password",
	match = { class = "^1password$" },
	workspace = "special:1password",
	float = true,
})
hl.window_rule({
	name = "scratchpad-spotify",
	match = { class = "^(spotify|Spotify)$" },
	workspace = "special:spotify",
	float = true,
})
