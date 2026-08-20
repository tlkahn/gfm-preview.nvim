describe("keymap", function()
  local gfm = require("gfm_preview")

  before_each(function()
    gfm.setup({ open_browser = false })
  end)

  it("setup installs a visual-mode mapping", function()
    assert.is_not_nil(vim.fn.maparg("<leader>mp", "v"))
    assert.is_not_nil(vim.fn.maparg("<leader>mp", "n"))
  end)

  it("visual callback exits visual mode after previewing", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "alpha line", "beta line" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("normal! V")
    assert.are.equal("V", vim.fn.mode())

    local cb = vim.fn.maparg("<leader>mp", "v", false, true)
    assert.is_not_nil(cb.callback)
    assert.is_true(pcall(cb.callback))

    -- drain the <Esc> the callback queued via nvim_feedkeys
    vim.api.nvim_feedkeys("", "x", false)
    assert.are.equal("n", vim.fn.mode())
  end)
end)
