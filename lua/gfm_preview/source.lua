-- Extract markdown source from the current buffer or the last visual
-- selection, mirroring the Sublime plugin's selection-aware behavior.

local annotation = require("gfm_preview.preprocess.annotation")

local M = {}

--- Whole buffer text (including a trailing newline when present).
---@return string
local function buffer_text()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  return table.concat(lines, "\n")
end

--- Last visual selection as text, or nil when there is none / it is empty.
---@return string|nil
local function visual_selection()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  if start_pos[2] == 0 or end_pos[2] == 0 then
    return nil
  end
  local start_line, start_col = start_pos[2], start_pos[3]
  local end_line, end_col = end_pos[2], end_pos[3]
  if start_line == end_line and start_col == end_col then
    return nil
  end
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  if #lines == 0 then
    return nil
  end
  lines[1] = lines[1]:sub(start_col)
  if #lines > 1 then
    lines[#lines] = lines[#lines]:sub(1, end_col)
  else
    lines[1] = lines[1]:sub(1, end_col)
  end
  return table.concat(lines, "\n")
end

--- Visual selection if non-empty, otherwise the whole buffer.
---@return string
function M.buffer_or_visual()
  return visual_selection() or buffer_text()
end

--- Visual selection only; nil when nothing is selected.
---@return string|nil
function M.selection_only()
  return visual_selection()
end

--- Buffer/selection text that is a single Lit annotation body, or nil.
---@param deps table|nil injectable runner for tests
---@return string|nil
function M.annotation_body(deps)
  local text = M.buffer_or_visual()
  local body = annotation.extract_body(text, deps)
  if body == text then
    return nil
  end
  return body
end

return M
