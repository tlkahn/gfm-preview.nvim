describe("preprocess.graphviz", function()
  local graphviz = require("gfm_preview.preprocess.graphviz")

  it("wraps a graphviz fence in a hidden div", function()
    local input = "```graphviz\ndigraph G {\n  a -> b;\n}\n```\n"
    local expected = "\n<div class=\"graphviz-src\" style=\"display:none\">\ndigraph G {\n  a -&gt; b;\n}\n</div>\n\n"
    assert.are.equal(expected, graphviz.preprocess(input))
  end)

  it("accepts the dot alias", function()
    local input = "```dot\nstrict digraph {\n  rankdir=LR;\n}\n```\n"
    local expected = "\n<div class=\"graphviz-src\" style=\"display:none\">\nstrict digraph {\n  rankdir=LR;\n}\n</div>\n\n"
    assert.are.equal(expected, graphviz.preprocess(input))
  end)

  it("preserves surrounding text", function()
    local input = "Text\n\n```graphviz\ndigraph { a -> b }\n```\n\nmore"
    local expected = "Text\n\n\n<div class=\"graphviz-src\" style=\"display:none\">\ndigraph { a -&gt; b }\n</div>\n\n\nmore"
    assert.are.equal(expected, graphviz.preprocess(input))
  end)

  it("escapes HTML special characters inside the source", function()
    local input = "```graphviz\ndigraph {\n  a -> b [label=\"x<y & z>w\"];\n}\n```\n"
    local expected = "\n<div class=\"graphviz-src\" style=\"display:none\">\ndigraph {\n  a -&gt; b [label=\"x&lt;y &amp; z&gt;w\"];\n}\n</div>\n\n"
    assert.are.equal(expected, graphviz.preprocess(input))
  end)

  it("leaves non-graphviz fences untouched", function()
    local input = "```mermaid\ngraph TD\nA-->B\n```\n"
    assert.are.equal(input, graphviz.preprocess(input))
  end)
end)
