describe("preprocess.excalidraw", function()
  local excalidraw = require("gfm_preview.preprocess.excalidraw")

  local function make_deps(behavior)
    local captured = {}
    local deps = {
      url = "https://kroki.io/excalidraw/svg",
      timeout_ms = 30000,
      captured = captured,
      http_post = function(url, body, opts)
        captured.url = url
        captured.body = body
        captured.opts = opts
        if behavior == "ok" then
          return { ok = true, body = "<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>" }
        elseif behavior == "http_error" then
          return { ok = false, err = "http", body = "bad request details\n" }
        elseif behavior == "http_error_html" then
          return { ok = false, err = "http", body = "bad <tag> & entity" }
        elseif behavior == "unreachable" then
          return { ok = false, err = "unreachable" }
        end
        error("unknown behavior " .. tostring(behavior))
      end,
    }
    return deps
  end

  it("wraps a successful Kroki response in a diagram div", function()
    local deps = make_deps("ok")
    local out = excalidraw.preprocess("```excalidraw\n{\"elements\": []}\n```\n", deps)
    assert.are.equal("\n<div class=\"excalidraw-diagram\"><svg xmlns=\"http://www.w3.org/2000/svg\"></svg></div>\n\n", out)
  end)

  it("posts the fence content to the Kroki endpoint", function()
    local deps = make_deps("ok")
    local input = "```excalidraw\n{\"elements\": [{\"id\": \"a\"}]}\n```\n"
    excalidraw.preprocess(input, deps)
    assert.are.equal("https://kroki.io/excalidraw/svg", deps.captured.url)
    assert.are.equal("{\"elements\": [{\"id\": \"a\"}]}\n", deps.captured.body)
    assert.are.equal(30000, deps.captured.opts.timeout)
  end)

  it("reports an HTTP error with the stripped body", function()
    local deps = make_deps("http_error")
    local out = excalidraw.preprocess("```excalidraw\nbad\n```\n", deps)
    assert.are.equal("\n<pre class=\"excalidraw-error\">Excalidraw error: bad request details</pre>\n\n", out)
  end)

  it("escapes HTML special characters in HTTP error bodies", function()
    local deps = make_deps("http_error_html")
    local out = excalidraw.preprocess("```excalidraw\nbad\n```\n", deps)
    assert.are.equal("\n<pre class=\"excalidraw-error\">Excalidraw error: bad &lt;tag&gt; &amp; entity</pre>\n\n", out)
  end)

  it("reports an unreachable Kroki service", function()
    local deps = make_deps("unreachable")
    local out = excalidraw.preprocess("```excalidraw\nbad\n```\n", deps)
    assert.are.equal("\n<pre class=\"excalidraw-error\">Kroki service unreachable</pre>\n\n", out)
  end)

  it("leaves non-excalidraw fences untouched", function()
    local deps = make_deps("ok")
    local input = "```python\nx = 1\n```\n"
    assert.are.equal(input, excalidraw.preprocess(input, deps))
  end)

  it("preserves surrounding text", function()
    local deps = make_deps("ok")
    local out = excalidraw.preprocess("before\n\n```excalidraw\n{}\n```\n\nafter\n", deps)
    assert.are.equal("before\n\n\n<div class=\"excalidraw-diagram\"><svg xmlns=\"http://www.w3.org/2000/svg\"></svg></div>\n\n\nafter\n", out)
  end)
end)
