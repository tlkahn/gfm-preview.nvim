describe("preprocess.d2", function()
  local d2 = require("gfm_preview.preprocess.d2")

  local function make_deps(behavior)
    local captured = {}
    local deps = {
      d2 = "d2",
      timeout_ms = 30000,
      captured = captured,
      run_cmd = function(argv, opts)
        captured.argv = argv
        captured.opts = opts
        if behavior == "success" then
          local src_fd = io.open(argv[2], "r")
          captured.src_content = src_fd:read("*a")
          src_fd:close()
          local f = io.open(argv[3], "w")
          f:write("<svg xmlns=\"http://www.w3.org/2000/svg\"><g/></svg>")
          f:close()
          return { code = 0, stderr = "" }
        elseif behavior == "error" then
          return { code = 1, stderr = "syntax error at line 1\n" }
        elseif behavior == "error_html" then
          return { code = 1, stderr = "bad <tag> & entity" }
        elseif behavior == "missing" then
          return { code = "missing", stderr = "" }
        elseif behavior == "timeout" then
          return { code = "timeout", stderr = "" }
        end
        error("unknown behavior " .. tostring(behavior))
      end,
    }
    return deps
  end

  it("renders a d2 fence to an inline SVG", function()
    local deps = make_deps("success")
    local input = "```d2\nx -> y\n```\n"
    local out = d2.preprocess(input, deps)
    assert.are.equal("\n<div class=\"d2-diagram\"><svg xmlns=\"http://www.w3.org/2000/svg\"><g/></svg></div>\n\n", out)
  end)

  it("passes the d2 source and output paths to the runner", function()
    local deps = make_deps("success")
    d2.preprocess("```d2\nx -> y\n```\n", deps)
    assert.are.equal("d2", deps.captured.argv[1])
    assert.matches("%.d2$", deps.captured.argv[2])
    assert.matches("%.svg$", deps.captured.argv[3])
    assert.are.equal(30000, deps.captured.opts.timeout)
  end)

  it("writes the fence content verbatim as the d2 source", function()
    local deps = make_deps("success")
    d2.preprocess("```d2\nx -> y\n```\n", deps)
    assert.are.equal("x -> y\n", deps.captured.src_content)
  end)

  it("reports a nonzero exit as an escaped error block", function()
    local deps = make_deps("error")
    local out = d2.preprocess("```d2\nbad\n```\n", deps)
    assert.are.equal("\n<pre class=\"d2-error\">D2 error: syntax error at line 1</pre>\n\n", out)
  end)

  it("escapes HTML special characters in error messages", function()
    local deps = make_deps("error_html")
    local out = d2.preprocess("```d2\nbad\n```\n", deps)
    assert.are.equal("\n<pre class=\"d2-error\">D2 error: bad &lt;tag&gt; &amp; entity</pre>\n\n", out)
  end)

  it("reports a missing d2 binary", function()
    local deps = make_deps("missing")
    local out = d2.preprocess("```d2\nx\n```\n", deps)
    assert.are.equal("\n<pre class=\"d2-error\">d2 CLI not found. Install: https://d2lang.com</pre>\n\n", out)
  end)

  it("reports a timeout", function()
    local deps = make_deps("timeout")
    local out = d2.preprocess("```d2\nx\n```\n", deps)
    assert.are.equal("\n<pre class=\"d2-error\">D2 rendering timed out</pre>\n\n", out)
  end)

  it("leaves non-d2 fences untouched", function()
    local deps = make_deps("success")
    local input = "```python\nx = 1\n```\n"
    assert.are.equal(input, d2.preprocess(input, deps))
  end)

  it("cleans up the temporary source and svg files", function()
    local deps = make_deps("success")
    d2.preprocess("```d2\nx -> y\n```\n", deps)
    local src = deps.captured.argv[2]
    local out = deps.captured.argv[3]
    local f = io.open(src, "r")
    assert.is_nil(f, "source file should be removed")
    f = io.open(out, "r")
    assert.is_nil(f, "svg file should be removed")
  end)

  it("preserves surrounding text", function()
    local deps = make_deps("success")
    local out = d2.preprocess("before\n\n```d2\nx\n```\n\nafter\n", deps)
    assert.are.equal("before\n\n\n<div class=\"d2-diagram\"><svg xmlns=\"http://www.w3.org/2000/svg\"><g/></svg></div>\n\n\nafter\n", out)
  end)

  it("handles multiple d2 fences", function()
    local deps = make_deps("success")
    local out = d2.preprocess("```d2\na\n```\n```d2\nb\n```\n", deps)
    assert.are.equal("\n<div class=\"d2-diagram\"><svg xmlns=\"http://www.w3.org/2000/svg\"><g/></svg></div>\n\n\n<div class=\"d2-diagram\"><svg xmlns=\"http://www.w3.org/2000/svg\"><g/></svg></div>\n\n", out)
  end)
end)
