-- Extract markdown source from the current buffer or the last visual
-- selection, mirroring the Sublime plugin's selection-aware behavior.

local annotation = require("gfm_preview.preprocess.annotation")
local percent = require("gfm_preview.percent")

local M = {}

--- Whole buffer text (including a trailing newline when present).
---@return string
function M.buffer_text()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  return table.concat(lines, "\n")
end

local VISUAL_MODES = { v = true, V = true, ["\22"] = true }

--- Text of the region between two getpos()-style positions.
---@param start_pos table
---@param end_pos table
---@param vtype string "v" / "V" / "\22" (blockwise)
---@return string
local function region_text(start_pos, end_pos, vtype)
  local region = vim.fn.getregion(start_pos, end_pos, { type = vtype })
  return table.concat(region, "\n")
end

--- Last visual selection as text, or nil when there is none / it is empty.
---@return string|nil
local function visual_selection()
  local mode = vim.fn.mode()
  if VISUAL_MODES[mode] then
    -- LIVE: called from a visual-mode mapping; the '<' / '>' marks are stale
    -- here, so read the region from the live visual anchors.
    local text = region_text(vim.fn.getpos("v"), vim.fn.getpos("."), mode)
    if text == "" then
      return nil
    end
    return text
  end
  -- FALLBACK: after leaving visual mode (:GfmPreviewSelection, API callers).
  local start_pos, end_pos = vim.fn.getpos("'<"), vim.fn.getpos("'>")
  if start_pos[2] == 0 or end_pos[2] == 0 then
    return nil
  end
  if start_pos[2] == end_pos[2] and start_pos[3] == end_pos[3] then
    return nil
  end
  local vtype = vim.fn.visualmode()
  if vtype == "" then
    vtype = "v"
  end
  local text = region_text(start_pos, end_pos, vtype)
  if text == "" then
    return nil
  end
  return text
end

--- Visual selection if non-empty, otherwise the whole buffer.
---@return string
function M.buffer_or_visual()
  return visual_selection() or M.buffer_text()
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

--- Whole buffer text prepared for markdown preview: percent cells extracted
--- for non-markdown filetypes, raw text for markdown filetypes.
---@return string
function M.buffer_markdown()
  return percent.prepare(M.buffer_text(), {
    filetype = vim.bo.filetype,
    commentstring = vim.bo.commentstring,
    mode = "buffer",
  })
end

--- Visual selection prepared for markdown preview, or nil when none.
---@return string|nil
function M.selection_markdown()
  local text = M.selection_only()
  if not text then
    return nil
  end
  return percent.prepare(text, {
    filetype = vim.bo.filetype,
    commentstring = vim.bo.commentstring,
    mode = "selection",
  })
end

return M
