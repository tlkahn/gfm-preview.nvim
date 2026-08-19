-- gfm_preview: GitHub-flavored Markdown preview in the system browser.
-- Migrated from the Sublime Text plugin GfmPreviewWithToc (TOC dropped).

local M = {}

local config = require("gfm_preview.config")

--- Apply user options over defaults.
---@param opts table|nil
function M.setup(opts)
  config.setup(opts)
end

return M
