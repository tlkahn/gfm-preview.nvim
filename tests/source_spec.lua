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
end)
