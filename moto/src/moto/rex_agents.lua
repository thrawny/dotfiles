-- Print every terminal block on this Rex server as one JSON list, with the
-- facts moto's Rex backend needs. One `rex do` of this file replaces a process
-- per session and per block.
local TERMINAL = "com.superlogical.terminal"
local found = {}
assert(rex.call("session.attach_all", { event_scope = "session" }))
local listing = assert(rex.call("session.list"))
for _, session in ipairs(listing.sessions) do
  local view = rex.session.view{ session_id = session.session_id } or {}
  for _, window in ipairs(view.windows or {}) do
    for _, layer in ipairs(window.layers or {}) do
      for _, block in ipairs(layer.blocks or {}) do
        if block.creator_name == TERMINAL then
          local function call(method)
            return rex.block.call(TERMINAL, method, {
              session_id = session.session_id,
              block_id = block.block_id,
            }) or {}
          end
          local process = call("process")
          table.insert(found, {
            session_id = session.session_id,
            window_id = window.window_id,
            block_id = block.block_id,
            label = block.label,
            records = call("program_status").records,
            title = call("title").title,
            child = process.child,
            foreground = process.foreground,
          })
        end
      end
    end
  end
end
-- An empty Lua table encodes as an object, so moto reads {} as no blocks.
print(rex.json.encode(found))
