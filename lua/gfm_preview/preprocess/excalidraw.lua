-- Replace ```excalidraw fenced blocks with inline SVG rendered via the
-- Kroki service. The HTTP client is injectable for tests (http_post).
-- Ported from GfmPreviewWithToc.py.

local html_escape = require("gfm_preview.preprocess.html_escape")

local M = {}

local DEFAULTS = {
  url = "https://kroki.io/excalidraw/svg",
  timeout_ms = 30000,
  ---@param url string
  ---@param body string
  ---@param opts table { timeout = number }
  ---@return table { ok = boolean, body = string|nil, err = "http"|"unreachable"|nil }
  http_post = function(url, body, opts)
    local timeout = tostring(math.floor(opts.timeout / 1000))
    local obj = vim.system({
      "curl", "-sS", "--max-time", timeout,
      "-X", "POST",
      "-H", "Content-Type: text/plain",
      "--data-binary", "@-",
      url,
    }, { text = true, stdin = body }, nil)
    local res = obj:wait(opts.timeout)
    -- curl exit codes: 0 ok, 22 HTTP error (body on stdout), 7 connect
    -- failure, 28 timeout. Python maps timeout/URLError to "unreachable".
    if res.code == 0 then
      return { ok = true, body = res.stdout }
    elseif res.code == 7 or res.code == 28 then
      return { ok = false, err = "unreachable" }
    else
      return { ok = false, err = "http", body = res.stdout or res.stderr }
    end
  end,
}

---@param code string
---@param deps table
---@return string
local function render_one(code, deps)
  local res = deps.http_post(deps.url, code, { timeout = deps.timeout_ms })
  if res.ok then
    return '\n<div class="excalidraw-diagram">' .. (res.body or "") .. "</div>\n"
  elseif res.err == "unreachable" then
    return '\n<pre class="excalidraw-error">Kroki service unreachable</pre>\n'
  else
    local error_body = html_escape.escape((res.body or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    return '\n<pre class="excalidraw-error">Excalidraw error: ' .. error_body .. "</pre>\n"
  end
end

---@param md_text string
---@param deps table|nil injectable http client for tests
---@return string
function M.preprocess(md_text, deps)
  deps = vim.tbl_extend("force", DEFAULTS, deps or {})
  return (md_text:gsub("```excalidraw\n(.-)```", function(code)
    return render_one(code, deps)
  end))
end

return M
