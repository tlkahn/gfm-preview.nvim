-- Default configuration and runtime option merging.

local M = {}

local DEFAULTS = {
  --- Path to the pandoc binary.
  pandoc = "pandoc",
  --- Path to the pandoc-crossref filter binary.
  pandoc_crossref = "pandoc-crossref",
  --- Path to the d2 CLI binary.
  d2 = "d2",
  --- Path to the lit-annotation CLI.
  lit_annotation = vim.fn.expand("~/bin/lit-annotation"),
  --- Whether to open the rendered HTML in the system browser.
  open_browser = true,
  --- Default keymap for previewing the buffer/selection. false disables it.
  keymap = "<leader>mp",
  --- Prefix for the temporary preview directory.
  tmp_prefix = "gfm_preview_",
}

local state = vim.deepcopy(DEFAULTS)

--- Merge user options into the runtime config.
---@param opts table|nil
function M.setup(opts)
  state = vim.tbl_deep_extend("force", state, opts or {})
end

--- Current resolved config.
---@return table
function M.get()
  return state
end

return M
