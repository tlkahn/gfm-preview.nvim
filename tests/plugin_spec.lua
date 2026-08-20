-- plenary's harness runs child nvim with --noplugin, so source the plugin
-- file explicitly (lazy.nvim does this at startup in real usage).
vim.cmd("runtime plugin/gfm_preview.lua")

describe("plugin commands", function()
  local orig_notify = vim.notify

  after_each(function()
    vim.notify = orig_notify
  end)

  it("defines the user commands", function()
    assert.are.equal(2, vim.fn.exists(":GfmPreview"))
    assert.are.equal(2, vim.fn.exists(":GfmPreviewSelection"))
    assert.are.equal(2, vim.fn.exists(":GfmPreviewAnnotation"))
  end)

  it("GfmPreviewAnnotation warns when no annotation body is present", function()
    require("gfm_preview").setup({ open_browser = false })
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "just plain text" })
    local notified
    vim.notify = function(msg, level)
      notified = { msg = msg, level = level }
    end
    vim.cmd("GfmPreviewAnnotation")
    assert.is_not_nil(notified)
    assert.matches("No annotation body found", notified.msg)
    assert.are.equal(vim.log.levels.WARN, notified.level)
  end)

  it("GfmPreviewSelection accepts a '<,'> range", function()
    require("gfm_preview").setup({ open_browser = false })
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "alpha", "beta", "gamma" })
    vim.api.nvim_buf_set_mark(0, "<", 2, 0, {})
    vim.api.nvim_buf_set_mark(0, ">", 3, 5, {})
    local ok, err = pcall(vim.cmd, "'<,'>GfmPreviewSelection")
    assert.is_true(ok, err)
    assert.is_nil((tostring(err or ""):find("E481", 1, true)))
  end)

  it("GfmPreview with a range still previews the whole buffer", function()
    require("gfm_preview").setup({ open_browser = false })
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "alpha", "beta", "gamma" })
    vim.api.nvim_buf_set_mark(0, "<", 2, 0, {})
    vim.api.nvim_buf_set_mark(0, ">", 3, 5, {})
    local ok, err = pcall(vim.cmd, "'<,'>GfmPreview")
    assert.is_true(ok, err)
    assert.is_nil((tostring(err or ""):find("E481", 1, true)))
  end)
end)
