describe("gfm_preview API", function()
  local gfm = require("gfm_preview")
  local orig_notify = vim.notify

  before_each(function()
    gfm.setup({ open_browser = false })
  end)

  after_each(function()
    vim.notify = orig_notify
  end)

  local function capture_notify()
    local notified
    vim.notify = function(msg, level)
      notified = { msg = msg, level = level }
    end
    return function()
      return notified
    end
  end

  it("previews markdown through the full pipeline with real pandoc", function()
    local text = table.concat({
      "> [!note]",
      "> hi",
      "",
      "```mermaid",
      "graph TD",
      "A-->B",
      "```",
      "",
    }, "\n")
    local html_path = gfm.preview(text)
    assert.is_string(html_path)
    local f = io.open(html_path, "r")
    local html = f:read("*a")
    f:close()
    assert.matches("mermaid", html)
    assert.matches("callout", html)
  end)

  it("runs the preprocessors before pandoc (mocked pandoc)", function()
    local argv
    local html_path = gfm.preview("```d2\nx -> y\n```\n", {
      d2 = {
        run_cmd = function(a)
          local f = io.open(a[3], "w")
          f:write("<svg/>")
          f:close()
          return { code = 0, stderr = "" }
        end,
      },
      pandoc = {
        run_cmd = function(a)
          argv = a
          local f = io.open(a[12], "w")
          f:write("out")
          f:close()
          return { code = 0, stderr = "" }
        end,
      },
    })
    assert.is_string(html_path)
    local f = io.open(argv[10], "r")
    local md = f:read("*a")
    f:close()
    assert.matches('class="d2%-diagram"', md)
  end)

  it("notifies and returns nil when pandoc fails", function()
    local get_notified = capture_notify()
    local res = gfm.preview("# x\n", {
      pandoc = {
        run_cmd = function()
          return { code = 3, stderr = "boom" }
        end,
      },
    })
    assert.is_nil(res)
    local notified = get_notified()
    assert.is_not_nil(notified)
    assert.matches("boom", notified.msg)
    assert.are.equal(vim.log.levels.ERROR, notified.level)
  end)

  it("preview_selection notifies when nothing is selected", function()
    local get_notified = capture_notify()
    pcall(vim.api.nvim_buf_del_mark, 0, "<")
    pcall(vim.api.nvim_buf_del_mark, 0, ">")
    assert.is_nil(gfm.preview_selection())
    local notified = get_notified()
    assert.is_not_nil(notified)
    assert.matches("No text selected", notified.msg)
  end)

  it("preview_selection previews the current selection", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "alpha", "beta" })
    vim.api.nvim_buf_set_mark(0, "<", 2, 0, {})
    vim.api.nvim_buf_set_mark(0, ">", 2, 3, {})
    local html_path = gfm.preview_selection()
    assert.is_string(html_path)
    local f = io.open(html_path, "r")
    local html = f:read("*a")
    f:close()
    assert.matches("beta", html)
  end)

  it("preview_selection previews the LIVE selection, not stale marks", function()
    -- isolated in a scratch buffer so buffer-0 marks stay unpolluted
    local scratch = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, scratch)
    vim.api.nvim_buf_set_lines(scratch, 0, -1, false, { "alpha", "beta" })
    -- stale marks on line 1; live linewise selection is on line 2
    vim.api.nvim_buf_set_mark(scratch, "<", 1, 0, {})
    vim.api.nvim_buf_set_mark(scratch, ">", 1, 4, {})
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    vim.cmd("normal! V")
    local html_path = gfm.preview_selection()
    vim.cmd("normal! \27")
    assert.is_string(html_path)
    local f = io.open(html_path, "r")
    local html = f:read("*a")
    f:close()
    assert.matches("beta", html)
    assert.is_nil(html:find("alpha", 1, true))
    vim.api.nvim_buf_delete(scratch, { force = true })
  end)

  it("preview_annotation notifies when no annotation body is found", function()
    local get_notified = capture_notify()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "plain text" })
    assert.is_nil(gfm.preview_annotation())
    local notified = get_notified()
    assert.is_not_nil(notified)
    assert.matches("No annotation body found", notified.msg)
  end)

  it("preview_annotation previews the extracted body", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "<!--- something --->" })
    local html_path = gfm.preview_annotation({
      annotation = {
        run_cmd = function()
          return { code = 0, stdout = '[{"body": "annotation body text"}]' }
        end,
      },
    })
    assert.is_string(html_path)
    local f = io.open(html_path, "r")
    local html = f:read("*a")
    f:close()
    assert.matches("annotation body text", html)
  end)

  it("does not open the browser when open_browser is disabled", function()
    local opened = false
    gfm.setup({ open_browser = false })
    local html_path = gfm.preview("# x\n", {
      pandoc = {
        run_cmd = function(a)
          local f = io.open(a[12], "w")
          f:write("out")
          f:close()
          return { code = 0, stderr = "" }
        end,
      },
      browser = {
        open_url = function()
          opened = true
        end,
      },
    })
    assert.is_string(html_path)
    assert.is_false(opened)
  end)

  it("opens the browser when open_browser is enabled", function()
    local opened
    gfm.setup({ open_browser = true })
    gfm.preview("# x\n", {
      pandoc = {
        run_cmd = function(a)
          local f = io.open(a[12], "w")
          f:write("out")
          f:close()
          return { code = 0, stderr = "" }
        end,
      },
      browser = {
        open_url = function(url)
          opened = url
        end,
      },
    })
    assert.is_string(opened)
    assert.matches("^file://", opened)
  end)

  -- Phase 8: percent-format wiring through the API
  local function preview_md_text(run)
    local argv
    local html_path = run({
      pandoc = {
        run_cmd = function(a)
          argv = a
          local f = io.open(a[12], "w")
          f:write("out")
          f:close()
          return { code = 0, stderr = "" }
        end,
      },
    })
    assert.is_string(html_path)
    for _, p in ipairs(argv) do
      if p:match("input%.md$") then
        local f = io.open(p, "r")
        local text = f:read("*a")
        f:close()
        return text
      end
    end
    return nil
  end

  it("preview_buffer extracts a python percent cell before pandoc", function()
    vim.bo.filetype = "python"
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "# %% [markdown]", "# # Hello", "#", "# Body." })
    local md = preview_md_text(function(opts)
      return gfm.preview_buffer(opts)
    end)
    assert.matches("^# Hello", md)
    assert.is_nil(md:find("# %%", 1, true))
    vim.bo.filetype = ""
  end)

  it("preview_buffer previews raw buffer for markdown filetypes", function()
    vim.bo.filetype = "markdown"
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "# %% [markdown]", "# raw md" })
    local md = preview_md_text(function(opts)
      return gfm.preview_buffer(opts)
    end)
    assert.is_not_nil(md:find("# %% [markdown]", 1, true))
    vim.bo.filetype = ""
  end)

  it("preview_selection strips comment leaders for a python selection", function()
    vim.bo.filetype = "python"
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "# %% [markdown]", "# ## Title", "# para" })
    vim.api.nvim_buf_set_mark(0, "<", 2, 0, {})
    vim.api.nvim_buf_set_mark(0, ">", 3, 6, {})
    local md = preview_md_text(function(opts)
      return gfm.preview_selection(opts)
    end)
    assert.matches("## Title", md)
    assert.is_nil(md:find("# ## Title", 1, true))
    vim.bo.filetype = ""
  end)

  it("direct preview does not auto-extract percent cells", function()
    local md = preview_md_text(function(opts)
      return gfm.preview("# %% [markdown]\n# x\n", opts)
    end)
    assert.is_not_nil(md:find("# %% [markdown]", 1, true))
  end)
end)
