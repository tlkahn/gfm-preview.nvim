-- Pseudocode / algorithm blocks with custom \newcommand macro support.
-- Ported from GfmPreviewWithToc.py (macros from YAML front matter and inline).

local html_escape = require("gfm_preview.preprocess.html_escape")

local M = {}

local function codepoint_char(cp)
  -- LuaJIT has no utf8 library; nr2char encodes the code point as UTF-8.
  return vim.fn.nr2char(cp)
end

--- Unescape YAML double-quoted string escape sequences (YAML 1.2 spec),
--- mirroring the Python reference implementation.
---@param s string
---@return string
function M.yaml_unescape(s)
  local out = {}
  local i = 1
  local n = #s
  while i <= n do
    if s:sub(i, i) == "\\" and i + 1 <= n then
      local c = s:sub(i + 1, i + 1)
      local simple = {
        ["\\"] = "\\", ['"'] = '"', ["/"] = "/",
        a = "\a", b = "\b", e = "\27", f = "\f", n = "\n", r = "\r",
        t = "\t", v = "\v", ["0"] = "\0", N = "\194\133", _ = "\194\160",
        L = "\226\128\168", P = "\226\128\169", [" "] = " ",
      }
      if simple[c] then
        out[#out + 1] = simple[c]
        i = i + 2
      elseif c == "x" and i + 3 <= n then
        out[#out + 1] = codepoint_char(tonumber(s:sub(i + 2, i + 3), 16))
        i = i + 4
      elseif c == "u" and i + 5 <= n then
        out[#out + 1] = codepoint_char(tonumber(s:sub(i + 2, i + 5), 16))
        i = i + 6
      elseif c == "U" and i + 9 <= n then
        out[#out + 1] = codepoint_char(tonumber(s:sub(i + 2, i + 9), 16))
        i = i + 10
      else
        out[#out + 1] = s:sub(i, i)
        i = i + 1
      end
    else
      out[#out + 1] = s:sub(i, i)
      i = i + 1
    end
  end
  return table.concat(out)
end

--- Mimic Python's `(?:[^{}]|\{[^{}]*\})*` followed by `}`: read a braced
--- argument/body starting at s[start] == "{", allowing one level of nested
--- braces. Returns the content and the position after the closing brace,
--- or nil if the group is unbalanced/malformed.
---@param s string
---@param start integer
---@return string|nil, integer|nil
local function read_braced(s, start)
  local i = start + 1
  local n = #s
  while i <= n do
    local c = s:sub(i, i)
    if c == "}" then
      return s:sub(start + 1, i - 1), i + 1
    elseif c == "{" then
      local close = s:find("}", i)
      if not close then
        return nil
      end
      if s:sub(i + 1, close - 1):find("[{}]") then
        return nil
      end
      i = close + 1
    else
      i = i + 1
    end
  end
  return nil
end

--- Collect and strip inline \newcommand definitions from a code block.
--- Returns the stripped code and the inline macros (ordered).
---@param code string
---@return string, table, table
local function collect_inline_defs(code)
  local inline = {}
  local order = {}
  local out = {}
  local i = 1
  local n = #code
  local ND = "\\newcommand"
  while i <= n do
    if code:sub(i, i + #ND - 1) == ND then
      local p = i + #ND
      local parsed = false
      if code:sub(p, p) == "{" and code:sub(p + 1, p + 1) == "\\" then
        local name_start = p + 2
        local name_end = code:find("[^%w]", name_start)
        if name_end and code:sub(name_end, name_end) == "}" then
          local name = code:sub(name_start, name_end - 1)
          local r = name_end + 1
          local nargs = 0
          if code:sub(r, r) == "[" then
            local digits_end = code:find("[^%d]", r + 1)
            if digits_end and code:sub(digits_end, digits_end) == "]" then
              nargs = tonumber(code:sub(r + 1, digits_end - 1))
              r = digits_end + 1
            end
          end
          if code:sub(r, r) == "{" then
            local body, nxt = read_braced(code, r)
            if body then
              if not inline[name] then
                order[#order + 1] = name
              end
              inline[name] = { nargs = nargs, body = body }
              i = nxt
              parsed = true
            end
          end
        end
      end
      if not parsed then
        out[#out + 1] = code:sub(i, i)
        i = i + 1
      end
    else
      out[#out + 1] = code:sub(i, i)
      i = i + 1
    end
  end
  return table.concat(out), inline, order
end

---@param code string
---@param name string
---@param body string
---@return string
local function expand_zero_arg(code, name, body)
  local pat = "\\" .. name
  local out = {}
  local i = 1
  local n = #code
  while i <= n do
    if code:sub(i, i + #pat - 1) == pat then
      local after = i + #pat
      local nextc = code:sub(after, after)
      if nextc == "" then
        out[#out + 1] = body
        i = after
      elseif nextc:match("%a") then
        -- negative lookahead: \se must not be followed by a letter
        out[#out + 1] = code:sub(i, i)
        i = i + 1
      else
        out[#out + 1] = body .. nextc
        i = after + 1
      end
    else
      out[#out + 1] = code:sub(i, i)
      i = i + 1
    end
  end
  return table.concat(out)
end

---@param code string
---@param name string
---@param body string
---@return string
local function expand_n_arg(code, name, body)
  local pat = "\\" .. name
  local out = {}
  local i = 1
  local n = #code
  while i <= n do
    if code:sub(i, i + #pat - 1) == pat then
      local after = i + #pat
      if code:sub(after, after) == "{" then
        local arg, nxt = read_braced(code, after)
        if arg then
          out[#out + 1] = body:gsub("#1", function()
            return arg
          end)
          i = nxt
        else
          out[#out + 1] = code:sub(i, i)
          i = i + 1
        end
      else
        out[#out + 1] = code:sub(i, i)
        i = i + 1
      end
    else
      out[#out + 1] = code:sub(i, i)
      i = i + 1
    end
  end
  return table.concat(out)
end

--- Parse latex_macros from YAML front matter. Returns the macro table and
--- the ordered name list (front matter order, inline names appended).
---@param md_text string
---@return table, table
function M.parse_front_matter_macros(md_text)
  local macros = {}
  local order = {}

  local fm = md_text:match("^%-%-%-\n(.-)\n%-%-%-")
  if not fm then
    return macros, order
  end

  -- Find `latex_macros:` at a line start; lm_at points at the key start.
  local lm_at
  if fm:sub(1, 13) == "latex_macros:" then
    lm_at = 1
  else
    local nl = fm:find("\nlatex_macros:", 1, true)
    lm_at = nl and (nl + 1) or nil
  end
  if not lm_at then
    return macros, order
  end

  -- Python: `latex_macros:\s*\n` - the items start after the last newline
  -- in the whitespace run following the key.
  local wpos = lm_at + 13
  local last_nl
  while wpos <= #fm do
    local c = fm:sub(wpos, wpos)
    if c:match("%s") then
      if c == "\n" then
        last_nl = wpos
      end
      wpos = wpos + 1
    else
      break
    end
  end
  if not last_nl then
    return macros, order
  end

  -- Consume item lines: whitespace, `-`, rest of line (finditer equivalent
  -- matches `-\s*"(.*?)"\s*$` per line).
  local pos = last_nl + 1
  local n = #fm
  while pos <= n do
    local ws = fm:match("^%s+", pos)
    if not ws then
      break
    end
    local after_ws = pos + #ws
    if fm:sub(after_ws, after_ws) ~= "-" then
      break
    end
    -- Rest of this line (Python `.*` then optional `\n?`).
    local line_end = fm:find("\n", after_ws) or (n + 1)
    local line = fm:sub(after_ws, line_end - 1)
    -- finditer: `-\s*"(.*?)"\s*$` within the line
    local content = line:match("%-%s*\"(.-)\"%s*$")
    if content then
      local unescaped = M.yaml_unescape(content)
      -- \newcommand{\name}[n]{body}
      local name, nargs, body = unescaped:match("^\\newcommand%{\\([%w]+)%}%[([%d]+)%]%{(.*)%}$")
      if name then
        macros[name] = { nargs = tonumber(nargs), body = body }
        order[#order + 1] = name
      else
        name, body = unescaped:match("^\\newcommand%{\\([%w]+)%}%{(.*)%}$")
        if name then
          macros[name] = { nargs = 0, body = body }
          order[#order + 1] = name
        end
      end
    end
    pos = line_end
    if pos <= n and fm:sub(pos, pos) == "\n" then
      pos = pos + 1
    end
  end

  return macros, order
end

--- Expand custom \newcommand macros that pseudocode.js cannot handle.
--- Strips inline definitions and expands over up to three passes.
---@param code string
---@param macros table
---@param order table
---@return string
function M.expand_macros(code, macros, order)
  local stripped, inline, inline_order = collect_inline_defs(code)
  code = stripped

  -- Merge: front matter first (in order), then inline-only names; inline
  -- values override front matter (Python {**macros, **inline_macros}).
  local merged = {}
  local merged_order = {}
  local seen = {}
  for _, name in ipairs(order or {}) do
    merged_order[#merged_order + 1] = name
    merged[name] = macros[name]
    seen[name] = true
  end
  for _, name in ipairs(inline_order) do
    merged[name] = inline[name]
    if not seen[name] then
      merged_order[#merged_order + 1] = name
      seen[name] = true
    end
  end

  for _ = 1, 3 do
    local prev = code
    for _, name in ipairs(merged_order) do
      local m = merged[name]
      if m.nargs == 0 then
        code = expand_zero_arg(code, name, m.body)
      else
        code = expand_n_arg(code, name, m.body)
      end
    end
    if code == prev then
      break
    end
  end

  return code
end

--- Convert bare `keyword` lines into `\State \textbf{keyword}`, matching the
--- Python reference semantics: the match is `^(%s*)keyword%s*$` (MULTILINE),
--- where the greedy `%s*$` consumes trailing whitespace up to a position where
--- `$` matches (end of string or right before a newline).
---@param code string
---@param keyword string
---@return string
local function fix_keyword_lines(code, keyword)
  local out = {}
  local i = 1
  local n = #code
  while i <= n do
    local at_line_start = i == 1 or code:sub(i - 1, i - 1) == "\n"
    if at_line_start then
      local indent = code:match("^%s*", i)
      local after_indent = i + #indent
      if code:sub(after_indent, after_indent + #keyword - 1) == keyword then
        -- Maximal whitespace run after the keyword; track the last newline.
        local j = after_indent + #keyword
        local last_nl
        local reached_end = true
        while j <= n and code:sub(j, j):match("%s") do
          if code:sub(j, j) == "\n" then
            last_nl = j
          end
          j = j + 1
        end
        if j > n then
          reached_end = true
        else
          reached_end = false
        end
        local match_end
        if reached_end then
          match_end = n + 1
        elseif last_nl then
          match_end = last_nl
        else
          match_end = nil
        end
        if match_end then
          out[#out + 1] = indent .. "\\State \\textbf{" .. keyword .. "}"
          i = match_end
        else
          out[#out + 1] = code:sub(i, i)
          i = i + 1
        end
      else
        out[#out + 1] = code:sub(i, i)
        i = i + 1
      end
    else
      out[#out + 1] = code:sub(i, i)
      i = i + 1
    end
  end
  return table.concat(out)
end

--- Strip/transform LaTeX commands not supported by pseudocode.js.
---@param code string
---@param macros table
---@param order table
---@return string
function M.sanitize(code, macros, order)
  code = M.expand_macros(code, macros, order)
  -- \label{...} is not supported
  code = code:gsub("\\label%{[^}]*%}", "")
  -- \begin{algorithmic}[1] -> \begin{algorithmic}
  code = code:gsub("(\\begin%{algorithmic%})%[%d+%]", function(b)
    return b
  end)
  -- \textcolor{color}{content} -> content
  code = code:gsub("\\textcolor%{[^}]*%}%{([^}]*)%}", function(c)
    return c
  end)
  -- bare "break" / "continue" -> \State \textbf{...}
  code = fix_keyword_lines(code, "break")
  code = fix_keyword_lines(code, "continue")
  return code
end

--- Replace ```pseudocode / ```algorithm blocks with raw HTML so pandoc
--- passes them through for the browser-side pseudocode.js renderer.
---@param md_text string
---@return string
function M.preprocess(md_text)
  local macros, order = M.parse_front_matter_macros(md_text)
  local function replace(code)
    code = M.sanitize(code, macros, order)
    code = html_escape.escape(code)
    return "\n<pre class=\"pseudocode\">\n" .. code .. "</pre>\n"
  end
  md_text = md_text:gsub("```pseudocode\n(.-)```", replace)
  return (md_text:gsub("```algorithm\n(.-)```", replace))
end

return M
