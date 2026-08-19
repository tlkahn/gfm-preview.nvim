-- Convert Obsidian-style callouts (> [!type]) into pandoc fenced divs.
-- Ported from GfmPreviewWithToc.py with a manual line scanner because Lua
-- patterns do not support quantifiers on capture groups.

local html_escape = require("gfm_preview.preprocess.html_escape")
local icons = require("gfm_preview.preprocess.callout_icons")

local M = {}

--- Mimic Python str.title(): each maximal run of alphanumerics is
--- capitalized (first char upper, rest lower).
---@param s string
---@return string
local function title_case(s)
  return (s:gsub("[%w]+", function(word)
    return word:sub(1, 1):upper() .. word:sub(2):lower()
  end))
end

--- Strip the leading ">" markers from callout body lines and trim the
--- surrounding whitespace of the whole body (Python: join + .strip()).
---@param body_raw string
---@return string
local function process_body(body_raw)
  local lines = {}
  for line in (body_raw .. "\n"):gmatch("(.-)\n") do
    if line:sub(1, 2) == "> " then
      lines[#lines + 1] = line:sub(3)
    elseif line:sub(1, 1) == ">" then
      lines[#lines + 1] = line:sub(2)
    else
      lines[#lines + 1] = line
    end
  end
  return (table.concat(lines, "\n"):gsub("^%s+", ""):gsub("%s+$", ""))
end

---@param md_text string
---@return string
function M.preprocess(md_text)
  local out = {}
  local pos = 1
  local n = #md_text

  while pos <= n do
    local at_line_start = pos == 1 or md_text:sub(pos - 1, pos - 1) == "\n"
    if at_line_start and md_text:sub(pos, pos) == ">" then
      local line_end = md_text:find("\n", pos)
      if not line_end then
        -- Python requires a newline after the header; at EOF it is not a callout.
        out[#out + 1] = md_text:sub(pos)
        break
      end
      local hdr = md_text:sub(pos, line_end - 1)
      local type_, fold, space, title =
        hdr:match("^> %[!([%w%-]+)%]([%+%-]?)( ?)([^\n]*)$")

      -- Valid header: after the type and optional fold marker, the rest is
      -- either empty or starts with a space (matches the Python regex).
      if type_ and (space == " " or title == "") then
        local raw_type = type_:lower()
        local css_type = icons.aliases[raw_type] or raw_type

        local custom_title
        if space == " " then
          custom_title = title
        end
        local rendered_title
        if custom_title == nil or custom_title == "" then
          rendered_title = title_case(raw_type:gsub("-", " "))
        else
          rendered_title = custom_title:gsub("^%s+", ""):gsub("%s+$", "")
        end

        local icon = icons.icons[css_type] or icons.icons.note

        -- Collect body lines (each must start with ">").
        local body_lines = {}
        local body_pos = line_end + 1
        while body_pos <= n do
          local body_line_end = md_text:find("\n", body_pos)
          local body_line
          if body_line_end then
            body_line = md_text:sub(body_pos, body_line_end - 1)
          else
            body_line = md_text:sub(body_pos)
          end
          if body_line:sub(1, 1) ~= ">" then
            break
          end
          body_lines[#body_lines + 1] = body_line
          if body_line_end then
            body_pos = body_line_end + 1
          else
            body_pos = n + 1
          end
        end
        local body = process_body(table.concat(body_lines, "\n"))

        local classes = ".callout .callout-" .. css_type
        if fold ~= "" then
          classes = classes .. " .callout-foldable"
          if fold == "-" then
            classes = classes .. " .is-collapsed"
          end
        end

        local parts = {}
        parts[#parts + 1] = "\n::: {" .. classes .. "}\n\n"
        parts[#parts + 1] = '<div class="callout-title">' .. icon
          .. '<span class="callout-title-inner">'
          .. html_escape.escape(rendered_title) .. "</span>"
        if fold ~= "" then
          parts[#parts + 1] = icons.fold_icon
        end
        parts[#parts + 1] = "</div>\n\n"
        parts[#parts + 1] = body .. "\n\n:::\n"
        out[#out + 1] = table.concat(parts)

        pos = body_pos
      else
        out[#out + 1] = md_text:sub(pos, line_end)
        pos = line_end + 1
      end
    else
      out[#out + 1] = md_text:sub(pos, pos)
      pos = pos + 1
    end
  end

  return table.concat(out)
end

return M
