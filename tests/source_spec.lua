describe("source", function()
  local source = require("gfm_preview.source")

  local function clear_selection()
    pcall(vim.api.nvim_buf_del_mark, 0, "<")
    pcall(vim.api.nvim_buf_del_mark, 0, ">")
  end

  before_each(function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      "line one",
      "line two",
      "line three",
    })
    clear_selection()
  end)

  it("returns the whole buffer when there is no selection", function()
    assert.are.equal("line one\nline two\nline three", source.buffer_or_visual())
  end)

  it("preserves a trailing newline in the buffer text", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a", "b", "" })
    assert.are.equal("a\nb\n", source.buffer_or_visual())
  end)

  it("returns the visual selection when present", function()
    -- nvim_buf_set_mark cols are 0-based: line 2 col 0 .. line 3 col 4
    vim.api.nvim_buf_set_mark(0, "<", 2, 0, {})
    vim.api.nvim_buf_set_mark(0, ">", 3, 3, {})
    assert.are.equal("line two\nline", source.buffer_or_visual())
  end)

  it("falls back to the whole buffer for an empty selection", function()
    vim.api.nvim_buf_set_mark(0, "<", 2, 0, {})
    vim.api.nvim_buf_set_mark(0, ">", 2, 0, {})
    assert.are.equal("line one\nline two\nline three", source.buffer_or_visual())
  end)

  it("selection_only returns the selection when present", function()
    vim.api.nvim_buf_set_mark(0, "<", 1, 0, {})
    vim.api.nvim_buf_set_mark(0, ">", 1, 3, {})
    assert.are.equal("line", source.selection_only())
  end)

  it("selection_only returns nil when there is no selection", function()
    assert.is_nil(source.selection_only())
  end)

  -- Phase 7: percent-format wiring
  it("buffer_markdown keeps markdown filetypes unchanged", function()
    vim.bo.filetype = "markdown"
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "# %% [markdown]", "# raw md" })
    assert.are.equal("# %% [markdown]\n# raw md", source.buffer_markdown())
    vim.bo.filetype = ""
  end)

  it("buffer_markdown extracts percent cells for a python buffer", function()
    vim.bo.filetype = "python"
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      "# %% [markdown]",
      "# # Hello",
      "#",
      "# Body.",
    })
    assert.are.equal("# Hello\n\nBody.", source.buffer_markdown())
    vim.bo.filetype = ""
  end)

  it("buffer_markdown returns original text for a python buffer with no cells", function()
    vim.bo.filetype = "python"
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "x = 1", "print(x)" })
    assert.are.equal("x = 1\nprint(x)", source.buffer_markdown())
    vim.bo.filetype = ""
  end)

  it("selection_markdown returns nil when nothing is selected", function()
    assert.is_nil(source.selection_markdown())
  end)

  it("selection_markdown strips comment leaders for the selected range", function()
    vim.bo.filetype = "python"
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "# %% [markdown]", "# ## Title", "# para" })
    vim.api.nvim_buf_set_mark(0, "<", 2, 0, {})
    vim.api.nvim_buf_set_mark(0, ">", 3, 6, {})
    assert.are.equal("## Title\npara", source.selection_markdown())
    vim.bo.filetype = ""
  end)

  it("selection_markdown does not strip on markdown", function()
    vim.bo.filetype = "markdown"
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "# looks like comment" })
    vim.api.nvim_buf_set_mark(0, "<", 1, 0, {})
    vim.api.nvim_buf_set_mark(0, ">", 1, 20, {})
    assert.are.equal("# looks like comment", source.selection_markdown())
    vim.bo.filetype = ""
  end)
end)

describe("live visual capture", function()
  local source = require("gfm_preview.source")
  local scratch

  -- Every test runs in a fresh scratch buffer: real visual selections leave the
  -- '< / '> marks stuck at v:maxcol cols (nvim_buf_set_mark cannot shrink them
  -- afterwards) and make visualmode() non-empty, so a shared buffer would
  -- pollute mark-seeded tests. visualmode() is "" in a brand-new buffer.
  before_each(function()
    scratch = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, scratch)
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(scratch) then
      vim.api.nvim_buf_delete(scratch, { force = true })
    end
  end)

  -- Enter visual mode with keys, run fn, then ALWAYS leave visual mode so
  -- later specs are not polluted by leftover visual state or updated marks.
  local function with_visual(keys, fn)
    vim.cmd("normal! " .. keys)
    local ok, err = pcall(fn)
    vim.cmd("normal! \27")
    if not ok then
      error(err)
    end
  end

  it("selection_only returns the LIVE visual selection, not stale marks", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "alpha line", "beta line", "gamma line" })
    -- stale marks from a previous selection on line 1
    vim.api.nvim_buf_set_mark(0, "<", 1, 0, {})
    vim.api.nvim_buf_set_mark(0, ">", 1, 10, {})
    vim.api.nvim_win_set_cursor(0, { 3, 1 })
    with_visual("V", function()
      assert.are.equal("gamma line", source.selection_only())
    end)
  end)

  it("captures charwise within one line", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abcdef" })
    with_visual("0v3l", function()
      assert.are.equal("abcd", source.selection_only())
    end)
  end)

  it("captures charwise across lines", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abcdef", "ghijkl" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    with_visual("vj", function()
      assert.are.equal("abcdef\ng", source.selection_only())
    end)
  end)

  it("captures linewise multi-line", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "alpha line", "beta line", "gamma line" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    with_visual("Vj", function()
      assert.are.equal("beta line\ngamma line", source.selection_only())
    end)
  end)

  it("captures blockwise as rectangle rows", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abc", "def", "ghi" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    with_visual("\22jl", function()
      assert.are.equal("ab\nde", source.selection_only())
    end)
  end)

  it("captures a single-char live selection", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abcdef" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    with_visual("v", function()
      assert.are.equal("a", source.selection_only())
    end)
  end)

  it("captures multibyte without cutting mid-character", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "héllo wörld" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    with_visual("0v2l", function()
      assert.are.equal("hél", source.selection_only())
    end)
  end)

  -- Phase 2: mark fallback path (after leaving visual mode)

  it("after leaving visual mode, marks give the just-finished selection", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "alpha line", "beta line", "gamma line" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    vim.cmd("normal! Vj")
    vim.cmd("normal! \27")
    assert.are.equal("V", vim.fn.visualmode())
    assert.are.equal("beta line\ngamma line", source.selection_only())
  end)

  it("linewise marks do not depend on v:maxcol column math", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "alpha line", "beta line", "gamma line" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("normal! Vjj")
    vim.cmd("normal! \27")
    assert.are.equal("alpha line\nbeta line\ngamma line", source.selection_only())
  end)

  it("visualmode empty falls back to charwise for seeded marks", function()
    -- no real visual mode ever entered in this buffer
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "line one", "line two", "line three" })
    vim.api.nvim_buf_set_mark(0, "<", 2, 0, {})
    vim.api.nvim_buf_set_mark(0, ">", 3, 3, {})
    assert.are.equal("", vim.fn.visualmode())
    assert.are.equal("line two\nline", source.selection_only())
  end)

  it("fallback seeded marks over multibyte do not cut mid-character", function()
    -- marks select the two chars "él" (0-based cols 1..3)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "héllo wörld" })
    vim.api.nvim_buf_set_mark(0, "<", 1, 1, {})
    vim.api.nvim_buf_set_mark(0, ">", 1, 3, {})
    assert.are.equal("él", source.selection_only())
  end)

  -- Phase 3: percent-format wiring with a live selection

  it("selection_markdown strips comment leaders for a LIVE python selection", function()
    vim.bo.filetype = "python"
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "# %% [markdown]", "# ## Title", "# para" })
    with_visual("2GVj", function()
      assert.are.equal("## Title\npara", source.selection_markdown())
    end)
    vim.bo.filetype = ""
  end)
end)
