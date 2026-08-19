-- Escape HTML special characters for safe embedding in HTML elements.
-- Matches the Sublime plugin: only & < > are escaped (quotes are not).

local M = {}

---@param text string
---@return string
function M.escape(text)
  return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

return M
