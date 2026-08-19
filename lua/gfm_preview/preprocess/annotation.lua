-- Extract the body of a single Lit annotation via the lit-annotation CLI.
-- The command runner is injectable for tests.
-- Ported from GfmPreviewWithToc.py.

local M = {}

local DEFAULTS = {
  cli = vim.fn.expand("~/bin/lit-annotation"),
  timeout_ms = 10000,
  ---@param argv string[]
  ---@param opts table { stdin = string, timeout = number }
  ---@return table { code = number|"missing"|"timeout", stdout = string }
  run_cmd = function(argv, opts)
    local ok, obj = pcall(vim.system, argv, { text = true, stdin = opts.stdin, timeout = opts.timeout }, nil)
    if not ok then
      return { code = "missing", stdout = "" }
    end
    local res = obj:wait(opts.timeout)
    if res.signal ~= 0 then
      return { code = "timeout", stdout = "" }
    end
    return { code = res.code, stdout = res.stdout or "" }
  end,
}

--- If md_text is a single Lit annotation, extract and return its body.
--- Returns the original text on any failure.
---@param md_text string
---@param deps table|nil injectable runner for tests
---@return string
function M.extract_body(md_text, deps)
  deps = vim.tbl_extend("force", DEFAULTS, deps or {})

  local stripped = md_text:gsub("^%s+", ""):gsub("%s+$", "")
  local has_delimiters = stripped:sub(1, 5) == "<!---" and stripped:sub(-4) == "--->"

  local argv = { deps.cli }
  if has_delimiters then
    argv[#argv + 1] = "--pretty"
  else
    argv[#argv + 1] = "--bare"
    argv[#argv + 1] = "--pretty"
  end

  local res = deps.run_cmd(argv, { stdin = stripped, timeout = deps.timeout_ms })
  if res.code ~= 0 then
    return md_text
  end

  local ok, annotations = pcall(vim.json.decode, res.stdout)
  if not ok or type(annotations) ~= "table" then
    return md_text
  end
  if #annotations == 1 and type(annotations[1]) == "table" and annotations[1].body ~= nil then
    return annotations[1].body
  end
  return md_text
end

return M
