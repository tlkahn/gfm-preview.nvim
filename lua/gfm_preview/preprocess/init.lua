-- Preprocess pipeline: applies every diagram/callout transform in the same
-- order as the Sublime plugin (TOC dropped).

local mermaid = require("gfm_preview.preprocess.mermaid")
local pseudocode = require("gfm_preview.preprocess.pseudocode")
local graphviz = require("gfm_preview.preprocess.graphviz")
local d2 = require("gfm_preview.preprocess.d2")
local excalidraw = require("gfm_preview.preprocess.excalidraw")
local callouts = require("gfm_preview.preprocess.callouts")

local M = {}

---@param md_text string
---@param deps table|nil injectable runners for d2/excalidraw
---@return string
function M.run(md_text, deps)
  deps = deps or {}
  md_text = mermaid.preprocess(md_text)
  md_text = pseudocode.preprocess(md_text)
  md_text = graphviz.preprocess(md_text)
  md_text = d2.preprocess(md_text, deps.d2)
  md_text = excalidraw.preprocess(md_text, deps.excalidraw)
  md_text = callouts.preprocess(md_text)
  return md_text
end

return M
