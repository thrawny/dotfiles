local M = {}

local location_methods = {
  gd = { method = "textDocument/definition", title = "LSP definitions", desc = "Goto Definition (review proxy)" },
  gD = { method = "textDocument/declaration", title = "LSP declarations", desc = "Goto Declaration (review proxy)" },
  gI = {
    method = "textDocument/implementation",
    title = "LSP implementations",
    desc = "Goto Implementation (review proxy)",
  },
  gy = {
    method = "textDocument/typeDefinition",
    title = "LSP type definitions",
    desc = "Goto Type Definition (review proxy)",
  },
  gr = {
    method = "textDocument/references",
    title = "LSP references",
    desc = "References (review proxy)",
    context = { includeDeclaration = true },
  },
}

local function original_to_modified_line(session, line)
  local diff_result = session.stored_diff_result
  if not diff_result or not diff_result.changes then
    return line
  end

  local delta = 0
  for _, change in ipairs(diff_result.changes) do
    if line < change.original.start_line then
      break
    end

    local orig_count = change.original.end_line - change.original.start_line
    local mod_count = change.modified.end_line - change.modified.start_line

    if line < change.original.end_line then
      return math.max(
        1,
        change.modified.start_line + math.min(line - change.original.start_line, math.max(mod_count - 1, 0))
      )
    end

    delta = delta + mod_count - orig_count
  end

  return math.max(1, line + delta)
end

local function flatten_locations(results)
  local locations = {}

  for _, response in pairs(results or {}) do
    if response.result then
      local result = response.result
      if result.uri or result.targetUri then
        result = { result }
      end
      for _, loc in ipairs(result) do
        local uri = loc.uri or loc.targetUri
        local range = loc.range or loc.targetSelectionRange or loc.targetRange
        if uri and range then
          table.insert(locations, { uri = uri, range = range })
        end
      end
    end
  end

  return locations
end

local function qf_items_from_locations(locations)
  local items = {}

  for _, loc in ipairs(locations) do
    local filename = vim.uri_to_fname(loc.uri)
    local lnum = loc.range.start.line + 1
    table.insert(items, {
      filename = filename,
      lnum = lnum,
      col = loc.range.start.character + 1,
      text = vim.trim((vim.fn.getbufline(vim.fn.bufadd(filename), lnum)[1] or "")),
    })
  end

  return items
end

local function open_locations(locations, title, jump_single)
  if #locations == 0 then
    vim.notify("No " .. title:lower() .. " found", vim.log.levels.INFO)
    return
  end

  if jump_single and #locations == 1 then
    local loc = locations[1]
    vim.cmd.edit(vim.fn.fnameescape(vim.uri_to_fname(loc.uri)))
    vim.api.nvim_win_set_cursor(0, { loc.range.start.line + 1, loc.range.start.character })
    return
  end

  vim.fn.setqflist({}, " ", { title = title, items = qf_items_from_locations(locations) })

  local ok, fzf = pcall(require, "fzf-lua")
  if ok then
    fzf.quickfix({ winopts = { title = title } })
  else
    vim.cmd("copen")
  end
end

local function show_hover(result)
  local contents = result and result.contents
  if not contents then
    vim.notify("No hover found", vim.log.levels.INFO)
    return
  end

  local lines = vim.lsp.util.convert_input_to_markdown_lines(contents)
  lines = vim.split(table.concat(lines, "\n"), "\n", { trimempty = true })
  if vim.tbl_isempty(lines) then
    vim.notify("No hover found", vim.log.levels.INFO)
    return
  end

  vim.lsp.util.open_floating_preview(lines, "markdown", { border = "rounded", focusable = true })
end

local function session_file_path(session)
  local rel_path = session.modified_path ~= "" and session.modified_path or session.original_path
  if not rel_path or rel_path == "" then
    return nil
  end

  if rel_path:match("^/") then
    return rel_path
  end

  return (session.git_root or vim.fn.getcwd()) .. "/" .. rel_path
end

local function real_position(session, cursor)
  local line = vim.api.nvim_get_current_buf() == session.original_bufnr
      and original_to_modified_line(session, cursor[1])
    or cursor[1]
  return { line = line - 1, character = cursor[2] }
end

local function with_real_lsp(session, callback)
  local real_path = session_file_path(session)
  if not real_path then
    vim.notify("No review file path for LSP proxy", vim.log.levels.WARN)
    return
  end

  if vim.fn.filereadable(real_path) ~= 1 then
    vim.notify("No working-tree file for LSP proxy: " .. real_path, vim.log.levels.WARN)
    return
  end

  local real_buf = vim.fn.bufadd(real_path)
  vim.fn.bufload(real_buf)

  local attempts = 0
  local function wait_for_lsp()
    attempts = attempts + 1
    local clients = vim.lsp.get_clients({ bufnr = real_buf })
    if #clients > 0 then
      callback(real_buf, real_path)
    elseif attempts < 20 then
      vim.defer_fn(wait_for_lsp, 250)
    else
      vim.notify("No LSP client for LSP proxy: " .. real_path, vim.log.levels.WARN)
    end
  end

  wait_for_lsp()
end

local function proxy_location(tabpage, lhs)
  if #vim.lsp.get_clients({ bufnr = 0 }) > 0 then
    local fallback = {
      gd = "FzfLua lsp_definitions jump1=true ignore_current_line=true",
      gD = "lua vim.lsp.buf.declaration()",
      gI = "FzfLua lsp_implementations jump1=true ignore_current_line=true",
      gy = "FzfLua lsp_typedefs jump1=true ignore_current_line=true",
      gr = "FzfLua lsp_references jump1=true ignore_current_line=true",
    }
    vim.cmd(fallback[lhs])
    return
  end

  local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
  local session = ok and lifecycle.get_session(tabpage)
  local spec = location_methods[lhs]
  if not session or not spec then
    vim.notify("No review session for LSP proxy", vim.log.levels.WARN)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  with_real_lsp(session, function(real_buf, real_path)
    local params = {
      textDocument = { uri = vim.uri_from_fname(real_path) },
      position = real_position(session, cursor),
    }
    if spec.context then
      params.context = spec.context
    end

    local results = vim.lsp.buf_request_sync(real_buf, spec.method, params, 10000)
    open_locations(flatten_locations(results), spec.title, lhs ~= "gr")
  end)
end

local function proxy_hover(tabpage)
  if #vim.lsp.get_clients({ bufnr = 0 }) > 0 then
    vim.lsp.buf.hover()
    return
  end

  local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
  local session = ok and lifecycle.get_session(tabpage)
  if not session then
    vim.notify("No review session for hover", vim.log.levels.WARN)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  with_real_lsp(session, function(real_buf, real_path)
    local results = vim.lsp.buf_request_sync(real_buf, "textDocument/hover", {
      textDocument = { uri = vim.uri_from_fname(real_path) },
      position = real_position(session, cursor),
    }, 10000)

    for _, response in pairs(results or {}) do
      if response.result then
        show_hover(response.result)
        return
      end
    end
    vim.notify("No hover found", vim.log.levels.INFO)
  end)
end

function M.apply(tabpage)
  local ok, lifecycle = pcall(require, "codediff.ui.lifecycle")
  local session = ok and lifecycle.get_session(tabpage)
  if not session then
    return
  end

  for _, bufnr in ipairs({ session.original_bufnr, session.modified_bufnr }) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buftype ~= "" then
      for lhs, spec in pairs(location_methods) do
        vim.keymap.set("n", lhs, function()
          proxy_location(tabpage, lhs)
        end, { buffer = bufnr, desc = spec.desc, silent = true })
      end
      vim.keymap.set("n", "K", function()
        proxy_hover(tabpage)
      end, { buffer = bufnr, desc = "Hover (review proxy)", silent = true })
    end
  end
end

return M
