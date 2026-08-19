describe("pandoc", function()
  local pandoc_mod = require("gfm_preview.pandoc")
  local assets = require("gfm_preview.assets")

  local function make_deps(behavior)
    local captured = {}
    local deps = {
      pandoc = "pandoc",
      pandoc_crossref = "pandoc-crossref",
      gfm_css = "https://cdnjs.cloudflare.com/ajax/libs/github-markdown-css/5.8.1/github-markdown.min.css",
      captured = captured,
      run_cmd = function(argv)
        captured.argv = argv
        if behavior == "ok" then
          -- mimic pandoc: write the output html
          local html_path = nil
          for i, a in ipairs(argv) do
            if a == "-o" then
              html_path = argv[i + 1]
            end
          end
          local f = io.open(html_path, "w")
          f:write("<html><body class=\"markdown-body\">rendered</body></html>")
          f:close()
          return { code = 0, stderr = "" }
        elseif behavior == "fail" then
          return { code = 2, stderr = "pandoc: unknown option" }
        end
        error("unknown behavior " .. tostring(behavior))
      end,
    }
    return deps
  end

  local function argv_flags(argv)
    local flags = {}
    for _, a in ipairs(argv) do
      flags[a] = true
    end
    return flags
  end

  it("disables yaml_metadata_block when the document has no front matter", function()
    local deps = make_deps("ok")
    pandoc_mod.render("# No front matter\n", deps)
    local flags = argv_flags(deps.captured.argv)
    assert.is_true(flags["markdown+tex_math_dollars+tex_math_single_backslash-yaml_metadata_block"])
    assert.is_nil(flags["markdown+tex_math_dollars+tex_math_single_backslash"])
  end)

  it("keeps yaml_metadata_block when the document starts with front matter", function()
    local deps = make_deps("ok")
    pandoc_mod.render("---\ntitle: T\n---\n\nbody\n", deps)
    local flags = argv_flags(deps.captured.argv)
    assert.is_true(flags["markdown+tex_math_dollars+tex_math_single_backslash"])
    assert.is_nil(flags["markdown+tex_math_dollars+tex_math_single_backslash-yaml_metadata_block"])
  end)

  it("passes the crossref filter and code block captions", function()
    local deps = make_deps("ok")
    pandoc_mod.render("# x\n", deps)
    local a = deps.captured.argv
    assert.are.equal("--filter", a[4])
    assert.are.equal("pandoc-crossref", a[5])
    assert.are.equal("-M", a[6])
    assert.are.equal("codeBlockCaptions=true", a[7])
  end)

  it("uses standalone, wrap=none and the GFM css", function()
    local deps = make_deps("ok")
    pandoc_mod.render("# x\n", deps)
    local flags = argv_flags(deps.captured.argv)
    assert.is_true(flags["--standalone"])
    assert.is_true(flags["--wrap=none"])
    assert.is_true(flags["--css=https://cdnjs.cloudflare.com/ajax/libs/github-markdown-css/5.8.1/github-markdown.min.css"])
  end)

  it("never passes --toc", function()
    local deps = make_deps("ok")
    pandoc_mod.render("# x\n", deps)
    assert.is_nil(deps.captured.argv["--toc"])
    for _, a in ipairs(deps.captured.argv) do
      assert.is_not_equal("--toc", a)
    end
  end)

  it("writes the markdown verbatim to the input file", function()
    local deps = make_deps("ok")
    local input = "# Hello\n\nSome *text*.\n"
    pandoc_mod.render(input, deps)
    local md_path = deps.captured.argv[10]
    local f = io.open(md_path, "r")
    assert.are.equal(input, f:read("*a"))
    f:close()
  end)

  it("writes the shell divs and header assets to include files", function()
    local deps = make_deps("ok")
    pandoc_mod.render("# x\n", deps)
    local a = deps.captured.argv
    local function read_after(flag)
      local path = nil
      for i, arg in ipairs(a) do
        if arg:sub(1, #flag) == flag then
          path = arg:sub(#flag + 2)
        end
      end
      local f = io.open(path, "r")
      local content = f:read("*a")
      f:close()
      return content
    end
    assert.are.equal(assets.SIMPLE_HTML_START, read_after("--include-before-body"))
    assert.are.equal(assets.SIMPLE_HTML_END, read_after("--include-after-body"))
    local header = read_after("--include-in-header")
    assert.matches("MathJax", header)
    assert.matches("mermaid", header)
    assert.matches("pseudocode", header)
    assert.matches("viz%-js", header)
    assert.matches("d2%-diagram", header)
    assert.matches("excalidraw%-diagram", header)
    assert.matches("callout", header)
    assert.matches("color%-scheme", header)
    assert.is_nil(header:find("TOC", 1, true)) -- no TOC assets
  end)

  it("returns the html path on success", function()
    local deps = make_deps("ok")
    local res = pandoc_mod.render("# x\n", deps)
    assert.is_true(res.ok)
    assert.is_string(res.html_path)
    assert.matches("%.html$", res.html_path)
    local f = io.open(res.html_path, "r")
    assert.is_not_nil(f)
    if f then f:close() end
  end)

  it("returns an error result when pandoc fails", function()
    local deps = make_deps("fail")
    local res = pandoc_mod.render("# x\n", deps)
    assert.is_false(res.ok)
    assert.matches("pandoc", res.err)
  end)
end)
