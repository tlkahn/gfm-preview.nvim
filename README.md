# gfm-preview.nvim

GitHub-flavored Markdown preview in the system browser, ported from the
Sublime Text plugin [GfmPreviewWithToc](https://github.com/abouolia/GfmPreviewWithToc)
with the sticky TOC dropped.

Renders Markdown with pandoc (GFM + MathJax) and supports the same
supplementary elements as the original plugin: mermaid, pseudocode with
`\newcommand` macros, graphviz/dot, d2, excalidraw (via Kroki), and
Obsidian-style callouts. Lit annotation body preview is included.

## Requirements

- Neovim >= 0.10 (uses `vim.fn.getregion`)
- [pandoc](https://pandoc.org) with [pandoc-crossref](https://github.com/lierdakil/pandoc-crossref)
- [d2](https://d2lang.com) (optional, for ` ```d2 ` blocks)
- `~/bin/lit-annotation` (optional, for `:GfmPreviewAnnotation`)
- Network access for CDN assets (MathJax, mermaid, KaTeX, pseudocode.js,
  viz.js, github-markdown-css) and the Kroki service for excalidraw

Rendering happens in the browser: the HTML is written to a temp dir
(`gfm_preview_*`) and opened with `file://`.

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
return {
  "tlkahn/gfm-preview.nvim",
  lazy = false,
  config = function()
    require("gfm_preview").setup()
  end,
}
```

For local development, point lazy at the checkout instead:
`dir = vim.fn.expand("~/Projects/gfm-preview.nvim")`.

## Usage

| Command | Action |
|---------|--------|
| `:GfmPreview` | Preview the whole buffer |
| `:GfmPreviewSelection` | Preview the current selection only |
| `:GfmPreviewAnnotation` | Preview the body of a single Lit annotation |

Default keymap: `<leader>mp` (normal mode previews the buffer, visual mode
previews the **live** selection and then exits visual mode). From visual mode
you can also use `:'<,'>GfmPreviewSelection` (or `:'<,'>GfmPreview` to ignore
the range and preview the whole buffer). `GfmPreviewAnnotation` has no
default keymap.

## Setup options

```lua
require("gfm_preview").setup({
  pandoc = "pandoc",                       -- pandoc binary
  pandoc_crossref = "pandoc-crossref",     -- crossref filter
  d2 = "d2",                               -- d2 CLI for ```d2 blocks
  lit_annotation = vim.fn.expand("~/bin/lit-annotation"),
  open_browser = true,                     -- false disables auto-open
  keymap = "<leader>mp",                   -- false disables the keymap
  tmp_prefix = "gfm_preview_",             -- temp dir prefix
})
```

## Supported markdown

- GitHub-flavored markdown via pandoc (`markdown+tex_math_dollars+tex_math_single_backslash`)
- LaTeX math rendered by MathJax (`$...$`, `$$...$$`, `\(...\)`, `\[...\]`)
- ` ```mermaid ` fenced blocks
- ` ```pseudocode ` / ` ```algorithm ` blocks with front-matter or inline
  `\newcommand` macro definitions (e.g. `\se`, `\search{...}`)
- ` ```graphviz ` / ` ```dot ` blocks (rendered client-side by viz.js)
- ` ```d2 ` blocks (rendered by the d2 CLI at preview time)
- ` ```excalidraw ` blocks (rendered by the Kroki service)
- Obsidian-style callouts `> [!note]`, `> [!warning]`, foldable variants
  `> [!success]+`, `> [!danger]-`, custom titles, and aliases
- Percent-format source files: non-markdown buffers (e.g. `python`, `r`,
  `javascript`, `lua`) with jupytext-style `# %% [markdown]` cells are
  extracted and uncommented (prefix + at most one space) before preview. Code
  cells (`# %%` without `[markdown]`) are omitted. Markdown filetypes stay
  raw. Selection preview strips comment leaders for the selected range only.
  Other line-comment prefixes such as `//` and `--` are supported. Block
  comments (`'''`, `/* */`) and `.ipynb` files are not handled.
- Figures/tables/cross-references via pandoc-crossref

## Development

Tests use [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) and
plenary.busted. Run the whole suite:

```sh
make test
```

Run a single spec:

```sh
make test-file FILE=tests/preprocess/callouts_spec.lua
```

Pure string transforms (callouts, pseudocode macros, mermaid, graphviz,
pipeline) are fuzz-verified byte-for-byte against the Python reference
implementation of GfmPreviewWithToc.

## Out of scope

- Sticky TOC / any TOC UI
- Live reload on save
- In-Neovim split/webview preview
