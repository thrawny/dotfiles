local M = {}

local function safe(fn, fallback)
  local ok, value = pcall(fn)
  if ok then
    return value
  end
  return fallback
end

local function command_output(command, cwd)
  local result = vim.system(command, { cwd = cwd, text = true }):wait()
  if result.code ~= 0 then
    return nil
  end
  return vim.trim(result.stdout or "")
end

local function tail_lines(text, limit)
  local lines = vim.split(text or "", "\n", { plain = true })
  if #lines <= limit then
    return lines
  end
  return vim.list_slice(lines, #lines - limit + 1, #lines)
end

local function collect_git(cwd)
  local root = command_output({ "git", "rev-parse", "--show-toplevel" }, cwd)
  if not root then
    return nil
  end
  return {
    root = root,
    branch = command_output({ "git", "branch", "--show-current" }, cwd),
    head = command_output({ "git", "rev-parse", "--short", "HEAD" }, cwd),
  }
end

local function collect_lsp(bufnr)
  local clients = {}
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    clients[#clients + 1] = {
      id = client.id,
      name = client.name,
      root_dir = client.config and client.config.root_dir or nil,
    }
  end
  return clients
end

local function collect_buffer_diagnostics(bufnr)
  local counts = { error = 0, warn = 0, info = 0, hint = 0 }
  local samples = {}
  local severity_names = {
    [vim.diagnostic.severity.ERROR] = "error",
    [vim.diagnostic.severity.WARN] = "warn",
    [vim.diagnostic.severity.INFO] = "info",
    [vim.diagnostic.severity.HINT] = "hint",
  }

  for _, diagnostic in ipairs(vim.diagnostic.get(bufnr)) do
    local severity = severity_names[diagnostic.severity] or tostring(diagnostic.severity)
    counts[severity] = (counts[severity] or 0) + 1
    if #samples < 10 then
      samples[#samples + 1] = {
        line = diagnostic.lnum + 1,
        column = diagnostic.col + 1,
        severity = severity,
        source = diagnostic.source,
        message = diagnostic.message,
      }
    end
  end

  return { counts = counts, samples = samples }
end

local function collect_buffer_mappings(bufnr)
  local mappings = {}
  for _, mode in ipairs({ "n", "v", "i" }) do
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(bufnr, mode)) do
      if #mappings >= 50 then
        return mappings, true
      end
      mappings[#mappings + 1] = {
        mode = mode,
        lhs = mapping.lhs,
        rhs = mapping.rhs ~= "" and mapping.rhs or nil,
        callback = mapping.callback ~= nil,
        desc = mapping.desc,
        silent = mapping.silent == 1,
      }
    end
  end
  return mappings, false
end

local function collect_codediff(tabpage)
  local lifecycle = package.loaded["codediff.ui.lifecycle"]
  if not lifecycle then
    return { loaded = false }
  end

  local session = lifecycle.get_session(tabpage)
  if not session then
    return { loaded = true, active = false }
  end

  local changes = {}
  local all_changes = session.stored_diff_result and session.stored_diff_result.changes or {}
  for i, change in ipairs(all_changes) do
    if i > 50 then
      break
    end
    changes[#changes + 1] = {
      index = i,
      original = { change.original.start_line, change.original.end_line },
      modified = { change.modified.start_line, change.modified.end_line },
    }
  end

  return {
    loaded = true,
    active = true,
    review_active = session.codediff_review_active == true,
    mode = session.mode,
    layout = session.layout,
    suspended = session.suspended,
    single_pane = session.single_pane,
    git_root = session.git_root,
    paths = {
      original = session.original_path,
      modified = session.modified_path,
    },
    revisions = {
      original = session.original_revision,
      modified = session.modified_revision,
    },
    buffers = {
      original = session.original_bufnr,
      modified = session.modified_bufnr,
      result = session.result_bufnr,
    },
    windows = {
      original = session.original_win,
      modified = session.modified_win,
      result = session.result_win,
    },
    render = {
      sequence = session.render_seq,
      rendered_sequence = session.rendered_seq,
      pending = session.render_pending,
      pending_navigation = session.pending_navigation,
    },
    explorer_file = session.explorer and session.explorer.current_file_path or nil,
    hunk_count = #all_changes,
    hunks = changes,
    hunks_truncated = #all_changes > #changes,
  }
end

function M.collect()
  local version = vim.version()
  local bufnr = vim.api.nvim_get_current_buf()
  local winid = vim.api.nvim_get_current_win()
  local tabpage = vim.api.nvim_get_current_tabpage()
  local cursor = vim.api.nvim_win_get_cursor(winid)
  local cwd = vim.fn.getcwd()
  local mappings, mappings_truncated = collect_buffer_mappings(bufnr)
  local messages = safe(function()
    return vim.api.nvim_exec2("messages", { output = true }).output
  end, "")

  return {
    generated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    process = {
      pid = vim.fn.getpid(),
      servername = vim.v.servername,
      neovim = string.format(
        "%d.%d.%d%s",
        version.major,
        version.minor,
        version.patch,
        version.prerelease and "-dev" or ""
      ),
    },
    workspace = {
      cwd = cwd,
      git = collect_git(cwd),
    },
    editor = {
      mode = vim.api.nvim_get_mode().mode,
      tabpage = tabpage,
      tab_count = #vim.api.nvim_list_tabpages(),
      window = winid,
      window_count = #vim.api.nvim_tabpage_list_wins(tabpage),
      window_layout = vim.fn.winlayout(),
      buffer = bufnr,
      buffer_name = vim.api.nvim_buf_get_name(bufnr),
      cursor = { line = cursor[1], column = cursor[2] },
      line_count = vim.api.nvim_buf_line_count(bufnr),
      options = {
        buftype = vim.bo[bufnr].buftype,
        filetype = vim.bo[bufnr].filetype,
        modified = vim.bo[bufnr].modified,
        modifiable = vim.bo[bufnr].modifiable,
        readonly = vim.bo[bufnr].readonly,
        diff = vim.wo[winid].diff,
        scrollbind = vim.wo[winid].scrollbind,
        wrap = vim.wo[winid].wrap,
        winbar = vim.wo[winid].winbar,
      },
    },
    lsp_clients = collect_lsp(bufnr),
    diagnostics = collect_buffer_diagnostics(bufnr),
    buffer_mappings = mappings,
    buffer_mappings_truncated = mappings_truncated,
    codediff = collect_codediff(tabpage),
    recent_messages = tail_lines(messages, 30),
  }
end

function M.copy()
  local report = "Neovim diagnostic bundle\n\n" .. vim.inspect(M.collect())
  vim.fn.setreg("+", report)
  vim.notify(string.format("Copied Neovim diagnostics (%d characters)", #report))
  return report
end

return M
