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
