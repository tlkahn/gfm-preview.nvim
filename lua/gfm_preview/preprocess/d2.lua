-- Replace ```d2 fenced blocks with inline SVG rendered by the d2 CLI.
-- The command runner is injectable for tests (run_cmd).
-- Ported from GfmPreviewWithToc.py.

local html_escape = require("gfm_preview.preprocess.html_escape")

local M = {}

local DEFAULTS = {
  d2 = "d2",
  timeout_ms = 30000,
  ---@param argv string[]
  ---@param opts table { timeout = number }
  ---@return table { code = number|"missing"|"timeout", stderr = string }
  run_cmd = function(argv, opts)
    local ok, res = pcall(vim.system, argv, { text = true, timeout = opts.timeout }, nil)
    if not ok then
      -- vim.system raises when the executable is not found.
      return { code = "missing", stderr = "" }
    end
    res = res:wait(opts.timeout)
    if res.signal ~= 0 then
      return { code = "timeout", stderr = res.stderr or "" }
    end
    return { code = res.code, stderr = res.stderr or "" }
  end,
}

---@param code string
---@param deps table
---@return string
local function render_one(code, deps)
  local src = vim.fn.tempname() .. ".d2"
  local out = src:gsub("%.d2$", ".svg")

  local src_fd = io.open(src, "w")
  src_fd:write(code)
  src_fd:close()

  local res = deps.run_cmd({ deps.d2, src, out }, { timeout = deps.timeout_ms })

  local result
  if res.code == 0 then
    local svg_fd = io.open(out, "r")
    if svg_fd then
      local svg = svg_fd:read("*a")
      svg_fd:close()
      result = '\n<div class="d2-diagram">' .. svg .. "</div>\n"
    else
      result = '\n<pre class="d2-error">D2 error: no SVG output produced</pre>\n'
    end
  elseif res.code == "missing" then
    result = '\n<pre class="d2-error">d2 CLI not found. Install: https://d2lang.com</pre>\n'
  elseif res.code == "timeout" then
    result = '\n<pre class="d2-error">D2 rendering timed out</pre>\n'
  else
    local err = html_escape.escape((res.stderr or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    result = '\n<pre class="d2-error">D2 error: ' .. err .. "</pre>\n"
  end

  for _, p in ipairs({ src, out }) do
    pcall(vim.fn.delete, p)
  end
  return result
end

---@param md_text string
---@param deps table|nil injectable runner for tests
---@return string
function M.preprocess(md_text, deps)
  deps = vim.tbl_extend("force", DEFAULTS, deps or {})
  return (md_text:gsub("```d2\n(.-)```", function(code)
    return render_one(code, deps)
  end))
end

return M
