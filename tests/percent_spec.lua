describe("gfm_preview.percent", function()
  local percent

  before_each(function()
    percent = require("gfm_preview.percent")
  end)

  it("loads the module", function()
    assert.is_table(percent)
  end)

  -- Phase 1: uncomment_line (exact jupytext semantics)
  describe("uncomment_line", function()
    it("strips hash+space", function()
      assert.are.equal("# Title", percent.uncomment_line("# # Title", "#"))
    end)

    it("strips bare hash blank", function()
      assert.are.equal("", percent.uncomment_line("#", "#"))
    end)

    it("strips hash+space blank", function()
      assert.are.equal("", percent.uncomment_line("# ", "#"))
    end)

    it("keeps two-space md indent", function()
      assert.are.equal("  marked", percent.uncomment_line("#   marked", "#"))
    end)

    it("keeps nested list indent", function()
      assert.are.equal("    - item", percent.uncomment_line("#     - item", "#"))
    end)

    it("keeps fence body indent", function()
      assert.are.equal("        code", percent.uncomment_line("#         code", "#"))
    end)

    it("leaves non-comment line", function()
      assert.are.equal("print(1)", percent.uncomment_line("print(1)", "#"))
    end)

    it("strips slash-slash+space", function()
      assert.are.equal("## Hi", percent.uncomment_line("// ## Hi", "//"))
    end)

    it("strips bare slash-slash", function()
      assert.are.equal("", percent.uncomment_line("//", "//"))
    end)

    it("strips dash-dash+space", function()
      assert.are.equal("## Hi", percent.uncomment_line("-- ## Hi", "--"))
    end)

    it("strips only one prefix occcurrence", function()
      assert.are.equal("## head", percent.uncomment_line("### head", "#"))
    end)

    it("strips one prefix from a markdown heading", function()
      -- jupytext strips a single prefix; `## Title` -> `# Title`
      assert.are.equal("# Title", percent.uncomment_line("## Title", "#"))
    end)
  end)

  -- Phase 2: opener / boundary detectors
  describe("is_markdown_opener", function()
    it("matches a plain markdown opener", function()
      assert.is_true(percent.is_markdown_opener("# %% [markdown]", "#"))
    end)

    it("matches an opener with a trailing param", function()
      assert.is_true(percent.is_markdown_opener("# %% [markdown] lang=en", "#"))
    end)

    it("matches an opener with multiple params", function()
      assert.is_true(percent.is_markdown_opener("# %% [markdown] key=value more=1", "#"))
    end)

    it("matches an opener with no space after prefix", function()
      assert.is_true(percent.is_markdown_opener("#%% [markdown]", "#"))
    end)

    it("matches an opener with trailing spaces", function()
      assert.is_true(percent.is_markdown_opener("# %% [markdown]  ", "#"))
    end)

    it("matches with a slash-slash prefix", function()
      assert.is_true(percent.is_markdown_opener("// %% [markdown]", "//"))
    end)

    it("matches with a dash-dash prefix", function()
      assert.is_true(percent.is_markdown_opener("-- %% [markdown]", "--"))
    end)

    it("rejects a code cell", function()
      assert.is_false(percent.is_markdown_opener("# %%", "#"))
    end)

    it("rejects a raw cell", function()
      assert.is_false(percent.is_markdown_opener("# %% [raw]", "#"))
    end)

    it("rejects a non-markdown token", function()
      assert.is_false(percent.is_markdown_opener("# %% [md]", "#"))
    end)

    it("rejects a marker inside code", function()
      assert.is_false(percent.is_markdown_opener('print("# %% [markdown]")', "#"))
    end)

    it("rejects an empty line", function()
      assert.is_false(percent.is_markdown_opener("", "#"))
    end)

    it("rejects a markdown-looking body line", function()
      assert.is_false(percent.is_markdown_opener("# ## Title", "#"))
    end)
  end)

  describe("is_cell_boundary", function()
    it("matches a bare code cell", function()
      assert.is_true(percent.is_cell_boundary("# %%", "#"))
    end)

    it("matches a markdown opener", function()
      assert.is_true(percent.is_cell_boundary("# %% [markdown]", "#"))
    end)

    it("matches a raw cell", function()
      assert.is_true(percent.is_cell_boundary("# %% [raw]", "#"))
    end)

    it("rejects a cell with no boundary token", function()
      assert.is_false(percent.is_cell_boundary("# %%foo", "#"))
    end)

    it("rejects a broken marker", function()
      assert.is_false(percent.is_cell_boundary("# % %", "#"))
    end)

    it("matches with a slash-slash prefix", function()
      assert.is_true(percent.is_cell_boundary("// %%", "//"))
    end)

    it("rejects a body line", function()
      assert.is_false(percent.is_cell_boundary("# code", "#"))
    end)

    it("rejects an empty line", function()
      assert.is_false(percent.is_cell_boundary("", "#"))
    end)
  end)

  -- Phase 3: extract_buffer single cell
  describe("extract_buffer", function()
    it("extracts a simple python markdown cell", function()
      local input = table.concat({
        "# %% [markdown]",
        "# # Hello",
        "#",
        "# Body.",
      }, "\n")
      assert.are.equal("# Hello\n\nBody.", percent.extract_buffer(input, "#"))
    end)

    it("drops opener params", function()
      local input = table.concat({
        "# %% [markdown] lang=en",
        "# Second cell.",
      }, "\n")
      assert.are.equal("Second cell.", percent.extract_buffer(input, "#"))
    end)

    it("extracts fenced code inside a cell", function()
      local input = table.concat({
        "# %% [markdown]",
        "# ```python",
        "# print(1)",
        "# ```",
      }, "\n")
      assert.are.equal("```python\nprint(1)\n```", percent.extract_buffer(input, "#"))
    end)

    it("preserves nested list indentation", function()
      local input = table.concat({
        "# %% [markdown]",
        "# - outer",
        "#   - inner",
      }, "\n")
      assert.are.equal("- outer\n  - inner", percent.extract_buffer(input, "#"))
    end)

    it("preserves math structurally", function()
      local input = table.concat({
        "# %% [markdown]",
        "# Inline $x$ and",
        "# $$",
        "# y=1",
        "# $$",
      }, "\n")
      assert.are.equal("Inline $x$ and\n$$\ny=1\n$$", percent.extract_buffer(input, "#"))
    end)

    it("preserves a trailing newline in the output when input ends with one", function()
      local input = "# %% [markdown]\n# # Hi\n"
      assert.are.equal("# Hi\n", percent.extract_buffer(input, "#"))
    end)

    -- Phase 4: multi-cell, code cells, passthrough
    it("omits code cells between markdown cells and joins by one blank line", function()
      local input = table.concat({
        "# %% [markdown]",
        "# # Hello",
        "#",
        "# Inline $x$ and a fence:",
        "#",
        "# ```python",
        "# print(1)",
        "# ```",
        "",
        "# %%",
        'print("code cell ignored by default")',
        "",
        "# %% [markdown] lang=en",
        "# Second cell.",
      }, "\n")
      local expected = table.concat({
        "# Hello",
        "",
        "Inline $x$ and a fence:",
        "",
        "```python",
        "print(1)",
        "```",
        "",
        "Second cell.",
      }, "\n")
      assert.are.equal(expected, percent.extract_buffer(input, "#"))
    end)

    it("ignores a leading jupytext header", function()
      local input = table.concat({
        "# ---",
        "# jupyter:",
        "#   jupytext:",
        "#     format_name: percent",
        "# ---",
        "#",
        "# %% [markdown]",
        "# Hi",
      }, "\n")
      assert.are.equal("Hi", percent.extract_buffer(input, "#"))
    end)

    it("returns original text unchanged when there are no markdown cells", function()
      local input = "# %%\nprint(1)\n"
      assert.are.equal(input, percent.extract_buffer(input, "#"))
    end)

    it("returns empty string for empty input", function()
      assert.are.equal("", percent.extract_buffer("", "#"))
    end)

    it("extracts a non-hash prefix cell", function()
      local input = table.concat({
        "// %% [markdown]",
        "// ## Title",
        "//",
        "// para",
      }, "\n")
      assert.are.equal("## Title\n\npara", percent.extract_buffer(input, "//"))
    end)

    it("handles markdown then code then EOF without final newline", function()
      local input = table.concat({
        "# %% [markdown]",
        "# A",
        "",
        "# %%",
        "code",
        "",
        "# %% [markdown]",
        "# B",
      }, "\n")
      assert.are.equal("A\n\nB", percent.extract_buffer(input, "#"))
    end)
  end)

  -- Phase 5: prepare_selection
  describe("prepare_selection", function()
    it("uncomments body lines with no opener", function()
      local input = table.concat({
        "# ## Title",
        "# para",
      }, "\n")
      assert.are.equal("## Title\npara", percent.prepare_selection(input, "#"))
    end)

    it("drops an included opener line", function()
      local input = table.concat({
        "# %% [markdown]",
        "# ## Title",
      }, "\n")
      assert.are.equal("## Title", percent.prepare_selection(input, "#"))
    end)

    it("drops a code boundary line and uncomments the rest", function()
      local input = table.concat({
        "# %%",
        "# not actually code in selection path",
      }, "\n")
      assert.are.equal("not actually code in selection path", percent.prepare_selection(input, "#"))
    end)

    it("preserves indentation after uncomment", function()
      local input = table.concat({
        "# - outer",
        "#   - inner",
      }, "\n")
      assert.are.equal("- outer\n  - inner", percent.prepare_selection(input, "#"))
    end)

    it("uncomments with a slash-slash prefix", function()
      local input = table.concat({
        "// ## Title",
        "// para",
      }, "\n")
      assert.are.equal("## Title\npara", percent.prepare_selection(input, "//"))
    end)

    it("returns empty string when only an opener is selected", function()
      assert.are.equal("", percent.prepare_selection("# %% [markdown]", "#"))
    end)
  end)

  -- Phase 6: filetype / prefix / prepare dispatch
  describe("is_markdown_filetype", function()
    it("recognizes markdown filetypes", function()
      for _, ft in ipairs({ "markdown", "markdown.pandoc", "md", "rmd", "quarto" }) do
        assert.is_true(percent.is_markdown_filetype(ft))
      end
    end)

    it("rejects non-markdown filetypes", function()
      for _, ft in ipairs({ "python", "lua", "javascript", "", nil }) do
        assert.is_false(percent.is_markdown_filetype(ft))
      end
    end)
  end)

  describe("prefix_for", function()
    it("honors an explicit prefix override", function()
      assert.are.equal("!", percent.prefix_for({ prefix = "!" }))
    end)

    it("maps known filetypes from the table", function()
      assert.are.equal("#", percent.prefix_for({ filetype = "python" }))
      assert.are.equal("//", percent.prefix_for({ filetype = "javascript" }))
      assert.are.equal("--", percent.prefix_for({ filetype = "lua" }))
    end)

    it("falls back to commentstring for unknown filetypes", function()
      assert.are.equal("#", percent.prefix_for({ filetype = "unknownlang", commentstring = "# %s" }))
      assert.are.equal("//", percent.prefix_for({ filetype = "unknownlang", commentstring = "// %s" }))
      assert.are.equal("--", percent.prefix_for({ filetype = "unknownlang", commentstring = "--%s" }))
    end)

    it("defaults to hash for unknown filetypes without commentstring", function()
      assert.are.equal("#", percent.prefix_for({ filetype = "unknownlang" }))
      assert.are.equal("#", percent.prefix_for({}))
    end)
  end)

  describe("prepare", function()
    it("returns markdown unchanged even in buffer mode", function()
      local text = "# %% [markdown]\n# raw md"
      assert.are.equal(text, percent.prepare(text, { filetype = "markdown", mode = "buffer" }))
    end)

    it("extracts percent cells for a python buffer", function()
      local text = table.concat({ "# %% [markdown]", "# # Hello", "#", "# Body." }, "\n")
      assert.are.equal("# Hello\n\nBody.", percent.prepare(text, { filetype = "python", mode = "buffer" }))
    end)

    it("returns identity for a python buffer with no cells", function()
      local text = "x = 1\nprint(x)\n"
      assert.are.equal(text, percent.prepare(text, { filetype = "python", mode = "buffer" }))
    end)

    it("uncomments a commented body for a python selection", function()
      local text = "# ## Title\n# para"
      assert.are.equal("## Title\npara", percent.prepare(text, { filetype = "python", mode = "selection" }))
    end)

    it("does not strip in markdown selection mode", function()
      local text = "# looks like comment"
      assert.are.equal(text, percent.prepare(text, { filetype = "markdown", mode = "selection" }))
    end)
  end)

  -- Phase 9: reference fixture golden test
  it("extracts the reference fixture to its expected golden output", function()
    local src = debug.getinfo(1, "S").source:sub(2)
    local dir = vim.fn.fnamemodify(src, ":h")
    local f = io.open(dir .. "/fixtures/percent_python.py", "r")
    local input = f:read("*a")
    f:close()
    local expected = table.concat({
      "# Hello",
      "",
      "Inline $x$ and a fence:",
      "",
      "```python",
      "print(1)",
      "```",
      "",
      "Second cell.",
    }, "\n") .. "\n"
    assert.are.equal(expected, percent.extract_buffer(input, "#"))
  end)
end)
