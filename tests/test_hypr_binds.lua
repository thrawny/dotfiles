-- Run without a compositor. Dispatch constructors only record their arguments.
package.path = "config/hypr/lua/?.lua;" .. package.path
local binds, events, calls = {}, {}, {}
local windows, active_special = {}, nil
local function dispatcher(name)
	return setmetatable({}, {
		__index = function(_, key)
			return dispatcher(name .. "." .. key)
		end,
		__call = function(_, ...)
			return { name = name, args = { ... } }
		end,
	})
end
hl = {
	dsp = dispatcher("dsp"),
	bind = function(key, callback) binds[key] = callback end,
	on = function(event, callback)
		events[event] = events[event] or {}
		table.insert(events[event], callback)
	end,
	dispatch = function(call) table.insert(calls, call) end,
	get_windows = function() return windows end,
	get_active_special_workspace = function() return active_special end,
	define_submap = function(_, _, callback) callback() end,
}
require("binds")
require("appjump")
local function opened(window)
	for _, callback in ipairs(events["window.open"]) do callback(window) end
end
for _, case in ipairs({
	{ "ALT + Q", "term", { class = "com.thrawny.GhosttyScratchpad" } },
	{ "ALT + O", "1password", { class = "1password" } },
	{ "ALT + P", "spotify", { class = "Spotify" } },
	{ "B", "btop", { title = "btop++" } },
}) do
	windows, active_special, calls = {}, nil, {}
	binds[case[1]]()
	assert(#calls == 1 and calls[1].name == "dsp.exec_cmd")
	opened({ class = "unrelated" })
	assert(#calls == 1)
	opened(case[3])
	assert(#calls == 2 and calls[2].name == "dsp.workspace.toggle_special")
	assert(calls[2].args[1] == case[2])
	opened(case[3])
	assert(#calls == 2, "must consume pending request")
	windows, calls = { case[3] }, {}
	binds[case[1]]()
	assert(#calls == 1 and calls[1].name == "dsp.workspace.toggle_special")
	windows, calls = {}, {}
	binds[case[1]]()
	active_special = { name = "special:" .. case[2] }
	opened(case[3])
	assert(#calls == 1, "must not hide an already visible scratchpad")
end
local directory = "/tmp/project with 'quotes' $(false); & spaces"
project_dir = function() return directory end
calls = {}
binds["ALT + Return"]()
local command = calls[1].args[1]
local quoted = assert(command:match("^ghostty %+new%-window %-%-working%-directory=(.*)$"))
local pipe = assert(io.popen("printf '%s' " .. quoted))
assert(pipe:read("*a") == directory, "shell must preserve the directory literally")
assert(pipe:close())
print("Hyprland binding tests passed")
