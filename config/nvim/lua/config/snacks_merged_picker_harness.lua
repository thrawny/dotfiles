local M = {}

local function out(line)
  vim.api.nvim_out_write(line .. "\n")
end

local function source_name(source_id)
  if source_id == 1 then
    return "files"
  elseif source_id == 2 then
    return "grep"
  end
  return tostring(source_id)
end

function M.run()
  local cwd = os.getenv("PICKER_CWD") or vim.fn.getcwd()
  local query = os.getenv("PICKER_QUERY") or "ghostty"
  local top_n = tonumber(os.getenv("PICKER_TOP") or "20") or 20

  vim.cmd("lcd " .. vim.fn.fnameescape(cwd))

  local picker = Snacks.picker(require("config.snacks_merged_picker").opts({
    title = "Find + Grep Harness",
    search = query,
  }))

  local finished = vim.wait(5000, function()
    return not picker:is_active()
  end, 20)

  if not finished then
    out("WARN: timed out waiting for picker tasks to finish")
  end

  local shown = 0
  local counts = { files = 0, grep = 0, other = 0 }

  for item in picker:iter() do
    shown = shown + 1
    local src = source_name(item.source_id)
    if counts[src] ~= nil then
      counts[src] = counts[src] + 1
    else
      counts.other = counts.other + 1
    end

    local label = item.file or item.text or "<no text>"
    out(string.format("%02d [%s] %s", shown, src, label))

    if shown >= top_n then
      break
    end
  end

  out(string.format("TOTAL shown=%d files=%d grep=%d other=%d", shown, counts.files, counts.grep, counts.other))
  picker:close()
end

return M
