-- Pandoc orchestration: write the temp files, build the argv, run pandoc.
-- The runner is injectable for tests.
-- Ported from GfmPreviewWithToc.py (TOC dropped).

local assets = require("gfm_preview.assets")

local M = {}

local DEFAULTS = {
  pandoc = "pandoc",
  pandoc_crossref = "pandoc-crossref",
  gfm_css = "https://cdnjs.cloudflare.com/ajax/libs/github-markdown-css/5.8.1/github-markdown.min.css",
  ---@param argv string[]
  ---@return table { code = number|"missing", stderr = string }
  run_cmd = function(argv)
    local ok, obj = pcall(vim.system, argv, { text = true }, nil)
    if not ok then
      return { code = "missing", stderr = "pandoc binary not found" }
    end
    local res = obj:wait()
    return { code = res.code, stderr = res.stderr or "" }
  end,
}

local function write_file(path, content)
  local f = io.open(path, "w")
  f:write(content)
  f:close()
end

local function temp_dir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  return dir
end

---Render preprocessed markdown to a standalone HTML file.
---@param md_text string
---@param deps table|nil injectable runner for tests
---@return table { ok = boolean, html_path = string|nil, err = string|nil }
function M.render(md_text, deps)
  deps = vim.tbl_extend("force", DEFAULTS, deps or {})

  local dir = temp_dir()
  local md_path = dir .. "/input.md"
  local html_path = dir .. "/preview.html"

  write_file(md_path, md_text)

  local before_path = dir .. "/before.html"
  local after_path = dir .. "/after.html"
  local header_path = dir .. "/header.html"
  write_file(before_path, assets.SIMPLE_HTML_START)
  write_file(after_path, assets.SIMPLE_HTML_END)
  write_file(
    header_path,
    assets.dark_mode_style
      .. assets.mathjax_script
      .. assets.mermaid_script
      .. assets.pseudocode_script
      .. assets.graphviz_script
      .. assets.d2_style
      .. assets.excalidraw_style
      .. assets.CALLOUT_STYLE
      .. assets.CALLOUT_SCRIPT
  )

  local fmt = "markdown+tex_math_dollars+tex_math_single_backslash"
  if md_text:sub(1, 3) ~= "---" then
    fmt = fmt .. "-yaml_metadata_block"
  end

  local argv = {
    deps.pandoc,
    "-f", fmt,
    "--filter", deps.pandoc_crossref,
    "-M", "codeBlockCaptions=true",
    "-t", "html",
    md_path,
    "-o", html_path,
    "--standalone",
    "--wrap=none",
    "--css=" .. deps.gfm_css,
    "--include-before-body=" .. before_path,
    "--include-after-body=" .. after_path,
    "--include-in-header=" .. header_path,
  }

  local res = deps.run_cmd(argv)
  if res.code ~= 0 then
    return { ok = false, err = res.stderr or ("pandoc exited with code " .. tostring(res.code)) }
  end
  return { ok = true, html_path = html_path }
end

return M
