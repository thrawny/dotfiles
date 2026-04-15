local M = {}

local function format_location(comment)
  local is_old = (comment.side or "new") == "old"
  if comment.line == 0 then
    return comment.file
  end

  if is_old then
    if comment.line_end and comment.line_end ~= comment.line then
      return string.format("%s:~%d-~%d", comment.file, comment.line, comment.line_end)
    end
    return string.format("%s:~%d", comment.file, comment.line)
  end

  if comment.line_end and comment.line_end ~= comment.line then
    return string.format("%s:%d-%d", comment.file, comment.line, comment.line_end)
  end
  return string.format("%s:%d", comment.file, comment.line)
end

local function generate_clipboard_text()
  local store = require("review.store")
  local all_comments = store.get_all()

  if #all_comments == 0 then
    return "No comments yet."
  end

  local lines = {
    "Review comments:",
    "",
  }

  for i, comment in ipairs(all_comments) do
    table.insert(lines, string.format("%d. `%s` - %s", i, format_location(comment), comment.text))
  end

  return table.concat(lines, "\n")
end

local function open_single_type_popup(initial_type, initial_text, callback)
  local ok_popup, Popup = pcall(require, "nui.popup")
  if not ok_popup then
    vim.ui.input({ prompt = "Comment: ", default = initial_text or "" }, function(text)
      if text and vim.trim(text) ~= "" then
        callback(initial_type or "note", vim.trim(text))
      else
        callback(nil, nil)
      end
    end)
    return
  end

  local prev_win = vim.api.nvim_get_current_win()
  local cfg = require("review.config").get()

  local popup = Popup({
    position = "50%",
    size = { width = 80, height = 8 },
    border = {
      style = "rounded",
      text = {
        top = " Comment (C-s: submit) ",
        top_align = "center",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
    },
    buf_options = {
      modifiable = true,
      readonly = false,
    },
  })

  local function restore_focus()
    vim.defer_fn(function()
      if prev_win and vim.api.nvim_win_is_valid(prev_win) then
        vim.api.nvim_set_current_win(prev_win)
      end
      vim.cmd("stopinsert")
    end, 10)
  end

  local function get_text()
    local lines = vim.api.nvim_buf_get_lines(popup.bufnr, 0, -1, false)
    local text = table.concat(lines, "\n"):gsub("%s+$", "")
    return text
  end

  local function submit()
    local text = get_text()
    popup:unmount()
    if text ~= "" then
      callback(initial_type or "note", text)
    else
      callback(nil, nil)
    end
    restore_focus()
  end

  local function close()
    popup:unmount()
    callback(nil, nil)
    restore_focus()
  end

  popup:mount()
  if initial_text and initial_text ~= "" then
    vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, vim.split(initial_text, "\n"))
  end

  vim.api.nvim_set_current_win(popup.winid)
  vim.cmd("startinsert")

  vim.keymap.set({ "i", "n" }, cfg.keymaps.popup_submit, submit, { buffer = popup.bufnr, noremap = true })
  vim.keymap.set("n", "<CR>", submit, { buffer = popup.bufnr, noremap = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = popup.bufnr, noremap = true })
  if cfg.keymaps.popup_cancel then
    vim.keymap.set("n", cfg.keymaps.popup_cancel, close, { buffer = popup.bufnr, noremap = true })
  end
end

function M.apply()
  require("review.popup").open = open_single_type_popup
  require("review.export").generate_markdown = generate_clipboard_text
end

return M
