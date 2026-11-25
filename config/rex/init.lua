-- Rex config for every Rex server of mine: the M1 app's local server and z13's
-- personal server. Each server runs this file for its own sessions, so the
-- agent keys below act on the host the app is showing.
--
-- Agents are terminals whose program reports a status with an app, as Claude
-- Code does. Their order is the sidebar's: sessions in session.list order, then
-- each window's blocks. Keys follow the Herdr desktop bindings in
-- docs/herdr-app.md.

local TERMINAL = "com.superlogical.terminal"
-- Cmd+O visits blocked agents first, then finished ones, then working ones.
local TIER = { blocked = 1, error = 2, done = 2, working = 3 }

local host = rex.exec({ "uname", "-n" })
if host and not host.stdout:match("^thrawny%-z13") then
  rex.host{ label = "z13", endpoint = "ssh://thrawny@thrawny-z13" }
end

-- The record a program keeps for itself, not one of its sub-records.
local function root_record(records)
  for _, record in ipairs(records or {}) do
    if record.id == nil and record.app then
      return record
    end
  end
end

local function agents()
  rex.call("session.attach_all", { event_scope = "session" })
  local found = {}
  local listing = rex.call("session.list") or { sessions = {} }
  for _, session in ipairs(listing.sessions) do
    local view = rex.session.view{ session_id = session.session_id } or {}
    for _, window in ipairs(view.windows or {}) do
      for _, layer in ipairs(window.layers or {}) do
        for _, block in ipairs(layer.blocks or {}) do
          if block.creator_name == TERMINAL then
            local status = rex.block.call(TERMINAL, "program_status", {
              session_id = session.session_id,
              block_id = block.block_id,
            }) or {}
            local record = root_record(status.records)
            if record then
              table.insert(found, {
                session_id = session.session_id,
                window_id = window.window_id,
                block_id = block.block_id,
                state = record.state,
                updated_at = record.updated_at or "",
              })
            end
          end
        end
      end
    end
  end
  return found
end

local function index_of(list, block_id)
  for i, agent in ipairs(list) do
    if agent.block_id == block_id then
      return i
    end
  end
end

local function focus(agent)
  if not agent then
    return
  end
  rex.session.focus_block{ session_id = agent.session_id, block_id = agent.block_id }
  rex.client.queue("session.select", {
    session_id = agent.session_id,
    window_id = agent.window_id,
  })
end

-- The agent step places after the caller's, wrapping; from outside an agent,
-- the first one going forward and the last one going back.
local function step(list, block_id, by)
  if #list == 0 then
    return nil
  end
  local i = index_of(list, block_id)
  if not i then
    return list[by > 0 and 1 or #list]
  end
  return list[(i - 1 + by) % #list + 1]
end

rex.action{
  name = "agent_goto",
  title = "Agents: Go to Number",
  args = { index = "integer" },
  run = function(ctx, args)
    focus(agents()[args.index])
  end,
}

rex.action{
  name = "agent_step",
  title = "Agents: Next or Previous",
  args = { by = "integer" },
  run = function(ctx, args)
    focus(step(agents(), ctx.block_id, args.by))
  end,
}

rex.action{
  name = "agent_attention",
  title = "Agents: Cycle Blocked, Done, Working",
  run = function(ctx)
    local ranked = {}
    for _, agent in ipairs(agents()) do
      if TIER[agent.state] then
        table.insert(ranked, agent)
      end
    end
    -- Oldest first within a tier. RFC 3339 times in one zone sort as text.
    table.sort(ranked, function(a, b)
      if TIER[a.state] ~= TIER[b.state] then
        return TIER[a.state] < TIER[b.state]
      end
      return a.updated_at < b.updated_at
    end)
    focus(step(ranked, ctx.block_id, 1))
  end,
}

rex.action{
  name = "session_shift",
  title = "Sessions: Move Down or Up",
  args = { by = "integer" },
  run = function(ctx, args)
    local listing = rex.call("session.list") or { sessions = {} }
    local ids = {}
    for _, session in ipairs(listing.sessions) do
      table.insert(ids, session.session_id)
    end
    local i
    for n, id in ipairs(ids) do
      if id == ctx.session_id then
        i = n
      end
    end
    if not i or (args.by > 0 and i == #ids) or (args.by < 0 and i == 1) then
      return
    end
    -- session.move places a session before another, or last without one.
    local before
    if args.by > 0 then
      before = ids[i + 2]
    else
      before = ids[i - 1]
    end
    rex.call("session.attach_all", { event_scope = "session" })
    rex.call("session.move", { session_id = ctx.session_id, before_session_id = before })
  end,
}

-- Home Manager writes Ghostty's colors, font and padding beside this file.
-- The settings belong to the app, so this only offers an action that sets
-- them, with Herdr's sidebar on the left: run "Apply Dotfiles Look" from the
-- command palette while the app shows this Mac. A second import of the same
-- theme fails, which leaves the theme already selected.
local look_file = io.open((os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config"))
  .. "/rex/ghostty-look.json")
if look_file then
  local look = rex.json.decode(look_file:read("*a"))
  look_file:close()
  rex.action{
    name = "dotfiles_look",
    title = "Apply Dotfiles Look",
    keywords = "ghostty theme font monokai appearance dark sidebar tabs left",
    run = function()
      local function set(name, value)
        rex.client.queue("client.setting." .. name, { value = value })
      end
      set("interface.appearance.scheme", "dark")
      -- Tabs down the left side; the "above" layout shows no sidebar.
      set("interface.toolbar.layout", "left")
      set("terminal.typography.font", look.font)
      set("terminal.typography.size", look.size)
      set("terminal.advanced_fonts.synthesize", look.synthesize)
      set("interface.pane_padding.horizontal", look.padding_x)
      set("interface.pane_padding.vertical", look.padding_y)
      set("terminal.cursor.blink", look.cursor_blink and "normal" or "off")
      if look.option_as_alt then
        set("terminal.keyboard.option", "sends_alt")
      end
      -- Importing selects the theme for the dark appearance set above.
      rex.client.queue("client.theme.import", { path = look.theme })
    end,
  }
end

for n = 1, 9 do
  rex.bind("cmd+[Digit" .. n .. "]", "agent_goto", { index = n })
end
rex.bind("cmd+j", "agent_step", { by = 1 })
rex.bind("cmd+k", "agent_step", { by = -1 })
rex.bind("cmd+o", "agent_attention")
rex.bind("shift+cmd+j", "session_shift", { by = 1 })
rex.bind("shift+cmd+k", "session_shift", { by = -1 })
rex.bind("cmd+b", "client.sidebar.toggle")
