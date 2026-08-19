describe("preprocess pipeline", function()
  local pipeline = require("gfm_preview.preprocess")

  local function ok_deps()
    return {
      d2 = {
        run_cmd = function(argv)
          local f = io.open(argv[3], "w")
          f:write("<svg class=\"d2-svg\"></svg>")
          f:close()
          return { code = 0, stderr = "" }
        end,
      },
      excalidraw = {
        http_post = function()
          return { ok = true, body = "<svg class=\"excalidraw-svg\"></svg>" }
        end,
      },
    }
  end

  it("applies all preprocessors in the Sublime order", function()
    local input = table.concat({
      "# Title",
      "",
      "```mermaid",
      "graph TD",
      "  A-->B",
      "```",
      "",
      "> [!note]",
      "> A callout",
      "",
      "```pseudocode",
      "\\State x",
      "```",
      "",
      "```graphviz",
      "digraph { a -> b }",
      "```",
      "",
      "```d2",
      "x -> y",
      "```",
      "",
      "```excalidraw",
      "{}",
      "```",
      "",
      "Math: $x^2$",
      "",
    }, "\n")

    local out = pipeline.run(input, ok_deps())

    assert.matches('%<pre class="mermaid"%>', out)
    assert.matches('%<pre class="pseudocode"%>', out)
    assert.matches('class="graphviz%-src"', out)
    assert.matches('class="d2%-diagram"%>%<svg class="d2%-svg"%>', out)
    assert.matches('class="excalidraw%-diagram"%>%<svg class="excalidraw%-svg"%>', out)
    assert.matches("%.callout %.callout%-note", out)
    assert.matches("%$x%^2%$", out) -- math source preserved for pandoc
    assert.matches("# Title", out) -- heading preserved
  end)

  it("equals sequential application of the preprocessors", function()
    local mermaid = require("gfm_preview.preprocess.mermaid")
    local pseudocode = require("gfm_preview.preprocess.pseudocode")
    local graphviz = require("gfm_preview.preprocess.graphviz")
    local d2 = require("gfm_preview.preprocess.d2")
    local excalidraw = require("gfm_preview.preprocess.excalidraw")
    local callouts = require("gfm_preview.preprocess.callouts")

    local input = "> [!tip]\n> hi\n\n```mermaid\ngraph TD\nA-->B\n```\n"
    local deps = ok_deps()

    local expected = input
    expected = mermaid.preprocess(expected)
    expected = pseudocode.preprocess(expected)
    expected = graphviz.preprocess(expected)
    expected = d2.preprocess(expected, deps.d2)
    expected = excalidraw.preprocess(expected, deps.excalidraw)
    expected = callouts.preprocess(expected)

    assert.are.equal(expected, pipeline.run(input, deps))
  end)
end)
