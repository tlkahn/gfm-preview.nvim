describe("preprocess.callouts", function()
  local callouts = require("gfm_preview.preprocess.callouts")
  local icons = require("gfm_preview.preprocess.callout_icons")

  -- Reconstruct the Python output shape from the shared icon data.
  local function expected(css, icon, title, fold, body)
    local fold_icon = fold and icons.fold_icon or ""
    local foldable = fold and " .callout-foldable" or ""
    local collapsed = fold == "-" and " .is-collapsed" or ""
    return "\n::: {.callout .callout-" .. css .. foldable .. collapsed .. "}\n\n"
      .. '<div class="callout-title">' .. icon
      .. '<span class="callout-title-inner">' .. title .. "</span>"
      .. fold_icon .. "</div>\n\n"
      .. body .. "\n\n:::\n"
  end

  it("converts a simple note callout (full golden parity)", function()
    local input = "> [!note]\n> Simple note body.\n"
    local expected_full = '\n::: {.callout .callout-note}\n\n'
      .. '<div class="callout-title">' .. icons.icons.note
      .. '<span class="callout-title-inner">Note</span></div>\n\n'
      .. "Simple note body.\n\n:::\n"
    assert.are.equal(expected_full, callouts.preprocess(input))
  end)

  it("lowercases an uppercase type", function()
    local input = "> [!NOTE]\n> Upper case type.\n"
    assert.are.equal(expected("note", icons.icons.note, "Note", nil, "Upper case type."), callouts.preprocess(input))
  end)

  it("uses the raw type for the default title, not the alias", function()
    local input = "> [!hint]\n> Alias of tip.\n"
    assert.are.equal(expected("tip", icons.icons.tip, "Hint", nil, "Alias of tip."), callouts.preprocess(input))
  end)

  it("uses a custom title", function()
    local input = "> [!warning] Custom Title Here\n> body line\n"
    assert.are.equal(expected("warning", icons.icons.warning, "Custom Title Here", nil, "body line"), callouts.preprocess(input))
  end)

  it("renders a foldable open callout", function()
    local input = "> [!success]+ Foldable open\n> content\n"
    assert.are.equal(expected("success", icons.icons.success, "Foldable open", "+", "content"), callouts.preprocess(input))
  end)

  it("renders a collapsed callout for the - marker", function()
    local input = "> [!danger]- Collapsed by default\n> secret\n"
    assert.are.equal(expected("danger", icons.icons.danger, "Collapsed by default", "-", "secret"), callouts.preprocess(input))
  end)

  it("falls back to the note icon for unknown types but keeps the class", function()
    local input = "> [!unknown-type]\n> Falls back to note icon.\n"
    assert.are.equal(expected("unknown-type", icons.icons.note, "Unknown Type", nil, "Falls back to note icon."), callouts.preprocess(input))
  end)

  it("keeps task list items inside the body", function()
    local input = "> [!todo]\n> - [ ] item one\n> - [x] item two\n"
    assert.are.equal(expected("todo", icons.icons.todo, "Todo", nil, "- [ ] item one\n- [x] item two"), callouts.preprocess(input))
  end)

  it("defaults the title when the header has only trailing spaces", function()
    local input = "> [!quote]  \n> quoted text\n"
    assert.are.equal(expected("quote", icons.icons.quote, "", nil, "quoted text"), callouts.preprocess(input))
  end)

  it("collapses blank quote-only body lines", function()
    local input = "> [!note] title\n> line one\n>\n> line three\n"
    assert.are.equal(expected("note", icons.icons.note, "title", nil, "line one\n\nline three"), callouts.preprocess(input))
  end)

  it("escapes HTML special characters in custom titles", function()
    local input = "> [!note] A <B> & C\n> x\n"
    assert.are.equal(expected("note", icons.icons.note, "A &lt;B&gt; &amp; C", nil, "x"), callouts.preprocess(input))
  end)

  it("preserves surrounding text", function()
    local input = "before\n\n> [!info]\n> info body\n\nafter\n"
    local callout = expected("info", icons.icons.info, "Info", nil, "info body")
    assert.are.equal("before\n\n" .. callout .. "\nafter\n", callouts.preprocess(input))
  end)

  it("does not treat a header without trailing newline as a callout", function()
    local input = "> [!note]"
    assert.are.equal(input, callouts.preprocess(input))
  end)

  it("does not treat a header with unspaced title text as a callout", function()
    local input = "> [!note]Title\n> x\n"
    assert.are.equal(input, callouts.preprocess(input))
  end)

  it("leaves an empty callout body as an empty fenced div", function()
    local input = "> [!note]\n\nmore\n"
    local callout = expected("note", icons.icons.note, "Note", nil, "")
    assert.are.equal(callout .. "\nmore\n", callouts.preprocess(input))
  end)

  it("treats a nested-looking callout line as body when it starts with >", function()
    local input = "> [!note]\n> a\n> [!tip]\n> b\n"
    local body = "a\n[!tip]\nb"
    assert.are.equal(expected("note", icons.icons.note, "Note", nil, body), callouts.preprocess(input))
  end)

  it("does not touch regular blockquotes", function()
    local input = "> regular quote\n> more\n"
    assert.are.equal(input, callouts.preprocess(input))
  end)
end)
