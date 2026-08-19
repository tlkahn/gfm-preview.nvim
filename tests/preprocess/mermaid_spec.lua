describe("preprocess.mermaid", function()
  local mermaid = require("gfm_preview.preprocess.mermaid")

  it("wraps a simple fence in a mermaid pre block", function()
    local input = "```mermaid\ngraph TD\n  A-->B\n```\n"
    local expected = "\n<pre class=\"mermaid\">\ngraph TD\n  A--&gt;B\n</pre>\n\n"
    assert.are.equal(expected, mermaid.preprocess(input))
  end)

  it("preserves surrounding text and escapes the arrow", function()
    local input = "Text before.\n\n```mermaid\nflowchart LR\n  A[Start] --> B{Decision}\n```\n\nText after."
    local expected = "Text before.\n\n\n<pre class=\"mermaid\">\nflowchart LR\n  A[Start] --&gt; B{Decision}\n</pre>\n\n\nText after."
    assert.are.equal(expected, mermaid.preprocess(input))
  end)

  it("converts \\n to <br/> then escapes it, and escapes arrows", function()
    -- Python: code.replace('\\n', '<br/>') then html-escape, so <br/> becomes &lt;br/&gt;
    local input = "```mermaid\nsequenceDiagram\n  A->>B: Hello\\nWorld\n```\n"
    local expected = "\n<pre class=\"mermaid\">\nsequenceDiagram\n  A-&gt;&gt;B: Hello&lt;br/&gt;World\n</pre>\n\n"
    assert.are.equal(expected, mermaid.preprocess(input))
  end)

  it("escapes fa icons so the browser does not parse them as tags", function()
    local input = "```mermaid\ngraph LR\n  A --> B[Use <fa:fa-arrow-right> icon]\n```\n"
    local expected = "\n<pre class=\"mermaid\">\ngraph LR\n  A --&gt; B[Use &lt;fa:fa-arrow-right&gt; icon]\n</pre>\n\n"
    assert.are.equal(expected, mermaid.preprocess(input))
  end)

  it("leaves non-mermaid fences untouched", function()
    local input = "```python\nx = 1\n```\n"
    assert.are.equal(input, mermaid.preprocess(input))
  end)

  it("handles multiple mermaid fences", function()
    local input = "```mermaid\ngraph TD\n  A-->B\n```\n```mermaid\nC-->D\n```\n"
    local expected = "\n<pre class=\"mermaid\">\ngraph TD\n  A--&gt;B\n</pre>\n\n\n<pre class=\"mermaid\">\nC--&gt;D\n</pre>\n\n"
    assert.are.equal(expected, mermaid.preprocess(input))
  end)
end)
