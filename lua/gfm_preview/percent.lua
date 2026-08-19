-- Percent-format source file extraction (jupytext `# %% [markdown]` cells).
-- Pure string API; no Neovim dependencies.

local M = {}

--- Strip a single line-comment prefix from a line using jupytext's uncomment
--- semantics: prefix + one space first, else bare prefix, else leave as-is.
---@param line string
---@param prefix string
---@return string
function M.uncomment_line(line, prefix)
  local prefix_and_space = prefix .. " "
  if line:sub(1, #prefix_and_space) == prefix_and_space then
    return line:sub(#prefix_and_space + 1)
  end
  if line:sub(1, #prefix) == prefix then
    return line:sub(#prefix + 1)
  end
  return line
end

--- Escape Lua-pattern magic chars so a prefix matches literally.
---@param s string
---@return string
local function literal_pat(s)
  return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1"))
end

--- True when the line is a percent markdown cell opener at BOL (no indent).
--- Matches: <prefix> \s* %% \s* [markdown]  (anything after is discarded).
---@param line string
---@param prefix string
---@return boolean
function M.is_markdown_opener(line, prefix)
  if prefix == "" then
    return false
  end
  local pat = "^" .. literal_pat(prefix) .. "%s*%%%%%s*%[markdown%]"
  return line:find(pat, 1) ~= nil
end

--- True when the line starts any percent cell (markdown, code, or raw), i.e.
--- it ends the previously open cell. Matches: <prefix> \s* %% followed by a
--- non-word char or end of line (token boundary).
---@param line string
---@param prefix string
---@return boolean
function M.is_cell_boundary(line, prefix)
  if prefix == "" or line:sub(1, #prefix) ~= prefix then
    return false
  end
  local rest = line:sub(#prefix + 1)
  if not rest:find("^%s*%%%%") then
    return false
  end
  local s2 = rest:find("%%%%")
  local after = rest:sub(s2 + 2)
  if after == "" then
    return true
  end
  return not after:sub(1, 1):match("%w")
end

--- Split text on \n preserving all empty lines and a trailing empty element
--- when the text ends with a newline (vim.split(plain) semantics).
---@param text string
---@return string[]
local function split_lines(text)
  local lines = {}
  local start = 1
  while true do
    local pos = text:find("\n", start, true)
    if not pos then
      lines[#lines + 1] = text:sub(start)
      break
    end
    lines[#lines + 1] = text:sub(start, pos - 1)
    start = pos + 1
  end
  return lines
end

--- Return the count of elements up to the last non-empty line, i.e. the number
--- of meaningful lines after dropping trailing blank lines.
---@param lines string[]
---@return integer
local function meaningful_count(lines)
  local n = #lines
  while n > 0 and lines[n] == "" do
    n = n - 1
  end
  return n
end

--- Extract all percent markdown cells joined by a single blank line, or return
--- the original text unchanged when there are no markdown cells. Code/raw cells
--- are omitted. A trailing newline in the input is mirrored in the output.
---@param text string
---@param prefix string
---@return string
function M.extract_buffer(text, prefix)
  local has_trailing_newline = text:sub(-1) == "\n"
  local lines = split_lines(text)
  -- A trailing newline yields a final empty element that is not body content;
  -- drop it and re-add the newline to the joined output instead.
  if has_trailing_newline and lines[#lines] == "" then
    lines[#lines] = nil
  end
  local cells = {}
  local current = nil
  local function flush()
    if not current then
      return
    end
    local n = meaningful_count(current)
    if n > 0 then
      cells[#cells + 1] = table.concat(current, "\n", 1, n)
    end
    current = nil
  end
  for _, line in ipairs(lines) do
    if M.is_markdown_opener(line, prefix) then
      flush()
      current = {}
    elseif M.is_cell_boundary(line, prefix) then
      flush()
    elseif current then
      current[#current + 1] = M.uncomment_line(line, prefix)
    end
  end
  flush()
  if #cells == 0 then
    return text
  end
  local out = table.concat(cells, "\n\n")
  if out ~= "" and has_trailing_newline then
    out = out .. "\n"
  end
  return out
end

--- Prepare a visual-selection slice for preview: uncomment every non-
--- opener/boundary line. Intentionally dumb (does not need surrounding cell
--- context); the buffer path is the smart extractor.
---@param text string
---@param prefix string
---@return string
function M.prepare_selection(text, prefix)
  local out = {}
  for _, line in ipairs(split_lines(text)) do
    if not M.is_markdown_opener(line, prefix) and not M.is_cell_boundary(line, prefix) then
      out[#out + 1] = M.uncomment_line(line, prefix)
    end
  end
  return table.concat(out, "\n")
end

-- Filetypes treated as already-markdown (identity path, never uncommenced).
local MD_FILETYPES = {
  markdown = true,
  ["markdown.pandoc"] = true,
  md = true,
  rmd = true,
  quarto = true,
}

--- True when the filetype is a markdown flavor that should be previewed raw.
---@param filetype string|nil
---@return boolean
function M.is_markdown_filetype(filetype)
  return filetype ~= nil and MD_FILETYPES[filetype] == true
end

-- Authoritative line-comment prefix per known filetype.
local FT_PREFIX = {
  python = "#", r = "#", julia = "#", ruby = "#", perl = "#",
  yaml = "#", toml = "#", sh = "#", bash = "#", zsh = "#", conf = "#",
  javascript = "//", typescript = "//", javascriptreact = "//",
  typescriptreact = "//", java = "//", c = "//", cpp = "//",
  rust = "//", go = "//", csharp = "//",
  lua = "--", sql = "--", haskell = "--",
}

--- Resolve the line-comment prefix: explicit override, known filetype table,
--- else commentstring, else "#".
---@param opts table|nil { prefix, filetype, commentstring }
---@return string
function M.prefix_for(opts)
  opts = opts or {}
  if opts.prefix and opts.prefix ~= "" then
    return opts.prefix
  end
  if opts.filetype then
    local from_ft = FT_PREFIX[opts.filetype]
    if from_ft then
      return from_ft
    end
  end
  if opts.commentstring then
    local marker = opts.commentstring:match("(.-)%%s")
    if marker then
      marker = marker:gsub("%s+$", "")
      if marker ~= "" then
        return marker
      end
    end
  end
  return "#"
end

--- Dispatch a buffer/selection text through the percent pipeline. Markdown
--- filetypes pass through unchanged; non-markdown text is extracted (buffer
--- mode) or uncommented (selection mode).
---@param text string
---@param opts table|nil { filetype, commentstring, prefix, mode }
---@return string
function M.prepare(text, opts)
  opts = opts or {}
  if M.is_markdown_filetype(opts.filetype) then
    return text
  end
  local prefix = M.prefix_for(opts)
  if opts.mode == "selection" then
    return M.prepare_selection(text, prefix)
  end
  return M.extract_buffer(text, prefix)
end

return M
