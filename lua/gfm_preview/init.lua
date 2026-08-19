-- gfm_preview: GitHub-flavored Markdown preview in the system browser.
-- Migrated from the Sublime Text plugin GfmPreviewWithToc (TOC dropped).

local M = {}

local config = require("gfm_preview.config")
local source = require("gfm_preview.source")
local preprocess = require("gfm_preview.preprocess")
local pandoc_mod = require("gfm_preview.pandoc")
local browser = require("gfm_preview.browser")

--- Apply user options and (re)install keymaps.
---@param opts table|nil
function M.setup(opts)
  config.setup(opts)
  local cfg = config.get()
  if cfg.keymap then
    vim.keymap.set("n", cfg.keymap, function()
      M.preview_buffer()
    end, { desc = "GfmPreview: preview buffer" })
    vim.keymap.set("v", cfg.keymap, function()
      M.preview_selection()
    end, { desc = "GfmPreview: preview selection" })
  end
end

--- Build injectable deps from the resolved config.
---@param opts table|nil
---@return table
local function build_deps(opts)
  opts = opts or {}
  local cfg = config.get()
  return {
    d2 = vim.tbl_extend("force", { d2 = cfg.d2 }, opts.d2 or {}),
    excalidraw = opts.excalidraw,
    pandoc = vim.tbl_extend("force", {
      pandoc = cfg.pandoc,
      pandoc_crossref = cfg.pandoc_crossref,
      tmp_prefix = cfg.tmp_prefix,
    }, opts.pandoc or {}),
  }
end

--- Core preview: preprocess, render with pandoc, open the browser.
--- Returns the html path on success, nil on failure.
---@param md_text string
---@param opts table|nil { pandoc/d2/excalidraw/browser deps, open_browser }
---@return string|nil
function M.preview(md_text, opts)
  opts = opts or {}
  local cfg = config.get()
  local deps = build_deps(opts)

  local processed = preprocess.run(md_text, deps)
  local res = pandoc_mod.render(processed, deps.pandoc)
  if not res.ok then
    vim.notify("Markdown preview failed:\n" .. tostring(res.err), vim.log.levels.ERROR)
    return nil
  end

  local open_browser = opts.open_browser
  if open_browser == nil then
    open_browser = cfg.open_browser
  end
  if open_browser then
    local browser_deps = opts.browser
    browser.open(res.html_path, browser_deps)
  end
  return res.html_path
end

--- Preview the whole buffer.
---@param opts table|nil
---@return string|nil
function M.preview_buffer(opts)
  return M.preview(source.buffer_markdown(), opts)
end

--- Preview the current selection only.
---@param opts table|nil
---@return string|nil
function M.preview_selection(opts)
  local text = source.selection_markdown()
  if not text then
    vim.notify("No text selected", vim.log.levels.WARN)
    return nil
  end
  return M.preview(text, opts)
end

--- Preview the body of a single Lit annotation from the buffer/selection.
---@param opts table|nil
---@return string|nil
function M.preview_annotation(opts)
  opts = opts or {}
  local body = source.annotation_body(opts.annotation)
  if not body then
    vim.notify("No annotation body found", vim.log.levels.WARN)
    return nil
  end
  return M.preview(body, opts)
end

return M
