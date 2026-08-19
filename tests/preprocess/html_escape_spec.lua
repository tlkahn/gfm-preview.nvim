describe("html_escape", function()
  local escape = require("gfm_preview.preprocess.html_escape").escape

  it("escapes ampersand", function()
    assert.are.equal("a &amp; b", escape("a & b"))
  end)

  it("escapes less-than", function()
    assert.are.equal("&lt;", escape("<"))
  end)

  it("escapes greater-than", function()
    assert.are.equal("&gt;", escape(">"))
  end)

  it("escapes all three together", function()
    assert.are.equal("&amp;&lt;&gt;", escape("&<>"))
  end)

  it("leaves plain text untouched", function()
    local text = "plain text with quotes \"quotes\" and 'apostrophes'"
    assert.are.equal(text, escape(text))
  end)

  it("escapes only & < > and not quotes (matches Sublime behavior)", function()
    assert.are.equal([[&lt;a href="x" title='y'&gt;&amp;&lt;/a&gt;]], escape([[<a href="x" title='y'>&</a>]]))
  end)
end)
