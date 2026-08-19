-- Open a rendered HTML file in the system browser. Injectable for tests.

local M = {}

local DEFAULTS = {
  open_url = function(url)
    vim.ui.open(url)
  end,
}

---@param html_path string
---@param deps table|nil injectable open_url for tests
---@return unknown
function M.open(html_path, deps)
  deps = vim.tbl_extend("force", DEFAULTS, deps or {})
  return deps.open_url("file://" .. html_path)
end

return M
