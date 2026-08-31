-- Per-workspace project directories: the Hyprland counterpart of niriusd's
-- workspace-directory map. The Lua table is only a live cache — hyprctl
-- reload destroys the Lua state (and fires on every config save), so the
-- state file in XDG_RUNTIME_DIR is the source of truth and is re-read at
-- config load. It must never be require'd or placed in the config dir, or
-- every write would trigger a full reload.
--
-- Shell access (bin/hyprland-project, ghostty spawns):
--   hyprctl eval 'set_project_dir("dotfiles", "/home/me/dotfiles")'
--   hyprctl repl 'return project_dir()'

local STATE = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/hypr-project-dirs"

PROJECT_DIRS = {}

-- Key by workspace name when set (stable across sessions), else id.
local function ws_key(ws)
	if ws == nil then
		return nil
	end
	if type(ws) == "string" or type(ws) == "number" then
		return tostring(ws)
	end
	local name = ws.name
	if name and name ~= "" then
		return name
	end
	return tostring(ws.id)
end

local function save()
	local f = io.open(STATE, "w")
	if not f then
		return
	end
	for key, dir in pairs(PROJECT_DIRS) do
		f:write(key, "\t", dir, "\n")
	end
	f:close()
end

local function load_state()
	local f = io.open(STATE, "r")
	if not f then
		return
	end
	for line in f:lines() do
		local key, dir = line:match("^([^\t]+)\t(.+)$")
		if key then
			PROJECT_DIRS[key] = dir
		end
	end
	f:close()
end

-- Globals on purpose: reachable from hyprctl eval/repl.
function set_project_dir(ws, dir)
	local key = ws_key(ws)
	if not key then
		return
	end
	if dir == nil or dir == "" then
		PROJECT_DIRS[key] = nil
	else
		PROJECT_DIRS[key] = dir
	end
	save()
end

function project_dir(ws)
	local key = ws_key(ws or hl.get_active_workspace())
	return key and PROJECT_DIRS[key]
end

load_state()

-- A removed workspace means the project was closed; drop its entry.
hl.on("workspace.removed", function(ws)
	set_project_dir(ws, nil)
end)
