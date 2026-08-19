-- Replace ```graphviz / ```dot fenced blocks with a hidden div that the
-- browser-side viz.js script turns into an SVG.

local html_escape = require("gfm_preview.preprocess.html_escape")

local M = {}

local function replace(code)
  code = html_escape.escape(code)
  return "\n<div class=\"graphviz-src\" style=\"display:none\">\n" .. code .. "</div>\n"
end

---@param md_text string
---@return string
function M.preprocess(md_text)
  -- Lua patterns have no alternation; run one gsub per fence keyword.
  md_text = md_text:gsub("```graphviz\n(.-)```", replace)
  return (md_text:gsub("```dot\n(.-)```", replace))
end

return M
