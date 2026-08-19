describe("integration (live pandoc)", function()
  local pandoc_mod = require("gfm_preview.pandoc")
  local has_tools = vim.fn.executable("pandoc") == 1 and vim.fn.executable("pandoc-crossref") == 1

  local function render_fixture(name)
    local path = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
      .. "/fixtures/"
      .. name
    local f = io.open(path, "r")
    local content = f:read("*a")
    f:close()
    local res = pandoc_mod.render(content)
    assert.is_true(res.ok, "pandoc should succeed: " .. tostring(res.err))
    local hf = io.open(res.html_path, "r")
    local html = hf:read("*a")
    hf:close()
    return html
  end

  it("renders a plain document to standalone HTML with GFM css", function()
    if not has_tools then
      pending("pandoc and pandoc-crossref required")
      return
    end
    local html = render_fixture("plain.md")
    assert.matches("markdown%-body", html)
    assert.matches("github%-markdown%-css", html)
    assert.matches("<h1", html)
    assert.matches("<strong>bold</strong>", html)
    assert.matches('<div class="sourceCode"', html)
  end)

  it("keeps math source intact for MathJax", function()
    if not has_tools then
      pending("pandoc and pandoc-crossref required")
      return
    end
    local html = render_fixture("math.md")
    -- pandoc renders inline math to HTML spans and keeps display math as
    -- raw TeX inside a span for MathJax to process.
    assert.matches('class="math inline"', html)
    assert.matches('class="math display"', html)
    assert.matches("%$%$", html)
    assert.matches("MathJax", html)
  end)
end)
