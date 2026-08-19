-- Replace ```mermaid fenced blocks with raw HTML so pandoc passes them through
-- and the browser-side mermaid script can render them.

local html_escape = require("gfm_preview.preprocess.html_escape")

local M = {}

--- Process escape sequences in mermaid node labels for proper rendering.
--- \n (literal backslash-n) becomes a line break marker.
---@param code string
---@return string
local function render_mermaid_text(code)
  return code:gsub("\\n", "<br/>")
end

---@param md_text string
---@return string
function M.preprocess(md_text)
  -- Lua's `.` matches any char including newlines; `.-` is non-greedy,
  -- matching the Python (DOTALL, non-greedy) behavior.
  -- A function replacement avoids Lua's `%` handling in gsub replacements.
  return (md_text:gsub("```mermaid\n(.-)```", function(code)
    code = render_mermaid_text(code)
    code = html_escape.escape(code)
    return "\n<pre class=\"mermaid\">\n" .. code .. "</pre>\n"
  end))
end

return M
