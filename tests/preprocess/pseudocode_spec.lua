describe("preprocess.pseudocode", function()
  local p = require("gfm_preview.preprocess.pseudocode")

  describe("yaml_unescape", function()
    it("passes plain text through", function()
      assert.are.equal("plain", p.yaml_unescape("plain"))
    end)
    it("unescapes \\n", function()
      assert.are.equal("a\nb", p.yaml_unescape("a\\nb"))
    end)
    it("unescapes \\t", function()
      assert.are.equal("tab\there", p.yaml_unescape("tab\\there"))
    end)
    it("unescapes \\uXXXX", function()
      assert.are.equal("é", p.yaml_unescape("\\u00e9"))
    end)
    it("unescapes \\xXX", function()
      assert.are.equal("A", p.yaml_unescape("\\x41"))
    end)
    it("unescapes \\UXXXXXXXX", function()
      assert.are.equal("😀", p.yaml_unescape("\\U0001F600"))
    end)
    it("keeps unknown escapes verbatim", function()
      assert.are.equal("bad\\qescape", p.yaml_unescape("bad\\qescape"))
    end)
    it("unescapes \\\\ to a single backslash", function()
      assert.are.equal("a\\b", p.yaml_unescape("a\\\\b"))
    end)
    it("unescapes \\\"", function()
      assert.are.equal('q"uote', p.yaml_unescape('q\\"uote'))
    end)
    it("handles a trailing backslash pair", function()
      assert.are.equal("trailing\\", p.yaml_unescape("trailing\\\\"))
    end)
  end)

  describe("parse_front_matter_macros", function()
    it("parses zero- and one-arg macros from YAML front matter", function()
      local doc = "---\ntitle: Test\nlatex_macros:\n"
        .. "  - \"\\\\newcommand{\\\\se}{\\\\mathcal{R}}\"\n"
        .. "  - \"\\\\newcommand{\\\\search}[1]{\\\\texttt{<search>} #1 \\\\texttt{</search>}}\"\n"
        .. "---\n\n# Heading\n"
      local macros = p.parse_front_matter_macros(doc)
      assert.are.same({ nargs = 0, body = "\\mathcal{R}" }, macros["se"])
      assert.are.same({ nargs = 1, body = "\\texttt{<search>} #1 \\texttt{</search>}" }, macros["search"])
    end)

    it("parses multi-arg macros", function()
      local doc = "---\nlatex_macros:\n  - \"\\\\newcommand{\\\\foo}[2]{#1+#2}\"\n---\n\nbody\n"
      local macros = p.parse_front_matter_macros(doc)
      assert.are.same({ nargs = 2, body = "#1+#2" }, macros["foo"])
    end)

    it("returns empty for documents without front matter", function()
      assert.are.same({}, p.parse_front_matter_macros("no front matter"))
    end)

    it("returns empty when latex_macros is absent", function()
      local doc = "---\ntitle: Test\n---\n\nbody\n"
      assert.are.same({}, p.parse_front_matter_macros(doc))
    end)
  end)

  describe("expand_macros", function()
    local macros = {
      se = { nargs = 0, body = "\\mathcal{R}" },
      search = { nargs = 1, body = "\\texttt{<search>} #1 \\texttt{</search>}" },
    }
    local order = { "se", "search" }

    it("expands a zero-arg macro", function()
      assert.are.equal("\\mathcal{R} is nice", p.expand_macros("\\se is nice", macros, order))
    end)

    it("does not expand when followed by a letter (negative lookahead)", function()
      assert.are.equal("\\seach", p.expand_macros("\\seach", macros, order))
    end)

    it("expands a one-arg macro", function()
      assert.are.equal("\\texttt{<search>} hello \\texttt{</search>}", p.expand_macros("\\search{hello}", macros, order))
    end)

    it("expands both macros together", function()
      local expected = "\\texttt{<search>} x \\texttt{</search>} \\mathcal{R}"
      assert.are.equal(expected, p.expand_macros("\\search{x} \\se", macros, order))
    end)

    it("expands nested macro references", function()
      assert.are.equal("\\texttt{<search>} \\mathcal{R} \\texttt{</search>}", p.expand_macros("\\search{\\se}", macros, order))
    end)

    it("strips inline newcommand definitions and expands them", function()
      assert.are.equal(" X \\mathcal{R}", p.expand_macros("\\newcommand{\\tmp}{X} \\tmp \\se", macros, order))
    end)

    it("expands inline one-arg definitions", function()
      assert.are.equal(" \\textbf{hello}", p.expand_macros("\\newcommand{\\baz}[1]{\\textbf{#1}} \\baz{hello}", macros, order))
    end)

    it("expands multi-arg macros using only the first braced argument", function()
      assert.are.equal(" a+#2{b}", p.expand_macros("\\newcommand{\\foo}[2]{#1+#2} \\foo{a}{b}", macros, order))
    end)

    it("expands nested definitions across passes", function()
      local m = {
        se = { nargs = 0, body = "\\mathcal{R}" },
        foo = { nargs = 2, body = "#1+#2" },
      }
      local o = { "se", "foo" }
      assert.are.equal(" x+#2", p.expand_macros("\\newcommand{\\nested}{\\foo{x}} \\nested", m, o))
    end)
  end)

  describe("sanitize", function()
    local macros = {
      se = { nargs = 0, body = "\\mathcal{R}" },
    }
    local order = { "se" }

    it("drops the optional line-numbering arg of algorithmic", function()
      assert.are.equal("\\begin{algorithmic}\n\\State x\n\\end{algorithmic}", p.sanitize("\\begin{algorithmic}[1]\n\\State x\n\\end{algorithmic}", macros, order))
    end)

    it("unwraps textcolor to its content", function()
      assert.are.equal("content", p.sanitize("\\textcolor{red}{content}", macros, order))
    end)

    it("removes labels", function()
      assert.are.equal(" \\State y", p.sanitize("\\label{foo} \\State y", macros, order))
    end)

    it("converts bare break lines to State bold break", function()
      assert.are.equal("\\State \\textbf{break}\n  \\State \\textbf{continue}\nx = 1\n\\State \\textbf{break}", p.sanitize("break\n  continue\nx = 1\nbreak", macros, order))
    end)

    it("expands macros before sanitizing", function()
      assert.are.equal("\\State \\mathcal{R}", p.sanitize("\\State \\se", macros, order))
    end)
  end)

  describe("preprocess", function()
    it("wraps a pseudocode fence in a pre block", function()
      local input = "```pseudocode\n\\begin{algorithm}\n\\State x\n\\end{algorithm}\n```\n"
      local expected = "\n<pre class=\"pseudocode\">\n\\begin{algorithm}\n\\State x\n\\end{algorithm}\n</pre>\n\n"
      assert.are.equal(expected, p.preprocess(input))
    end)

    it("accepts the algorithm alias", function()
      assert.are.equal("\n<pre class=\"pseudocode\">\n\\State y\n</pre>\n\n", p.preprocess("```algorithm\n\\State y\n```\n"))
    end)

    it("leaves non-pseudocode fences untouched", function()
      local input = "```python\nx = 1\n```\n"
      assert.are.equal(input, p.preprocess(input))
    end)

    it("applies front matter macros to fence content", function()
      local doc = "---\nlatex_macros:\n  - \"\\\\newcommand{\\\\se}{\\\\mathcal{R}}\"\n---\n\n"
        .. "```pseudocode\n\\se\n```\n"
      assert.are.equal("---\nlatex_macros:\n  - \"\\\\newcommand{\\\\se}{\\\\mathcal{R}}\"\n---\n\n\n<pre class=\"pseudocode\">\n\\mathcal{R}\n</pre>\n\n", p.preprocess(doc))
    end)

    it("converts bare break inside the fence", function()
      assert.are.equal("Text\n\n\n<pre class=\"pseudocode\">\n\\State \\textbf{break}</pre>\n\n\nafter", p.preprocess("Text\n\n```pseudocode\nbreak\n```\n\nafter"))
    end)

    it("escapes HTML special characters after macro expansion", function()
      local input = "```pseudocode\n\\texttt{<search>}\n```\n"
      assert.are.equal("\n<pre class=\"pseudocode\">\n\\texttt{&lt;search&gt;}\n</pre>\n\n", p.preprocess(input))
    end)
  end)
end)
