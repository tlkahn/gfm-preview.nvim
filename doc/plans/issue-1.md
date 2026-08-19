# Plan: Issue #1 - Percent-format markdown cells in non-md files

Track: https://github.com/tlkahn/gfm-preview.nvim/issues/1

## Goal

When the buffer is **not** markdown, extract jupytext-style percent markdown cells
(`# %% [markdown]` / `// %% [markdown]` / ...), strip the line-comment prefix with
**at most one** following space (jupytext `uncomment` semantics), and feed the
resulting markdown into the existing preprocess + pandoc pipeline.

Markdown filetypes stay identity. Code cells (`# %%` without `[markdown]`) are
omitted from buffer preview.

## Decisions locked in

| Topic | Choice |
|--------|--------|
| Placement | Pure module `lua/gfm_preview/percent.lua`; wired from `source.lua` |
| When | Only for non-markdown filetypes / explicit non-md opts |
| Uncomment | jupytext `cell_reader.uncomment`: prefix+one-space, else bare prefix, else keep |
| Extra spaces | Preserved (markdown indentation), never collapsed |
| Opener params | Anything after `[markdown]` on the opener line is accepted and discarded |
| Cell end | Next line matching `^<prefix>\s*%%\b` (any percent cell) or EOF |
| Multi-cell join | Document order, separated by a single blank line |
| No cells found | Return original text unchanged (non-md passthrough) |
| Selection | Uncomment selected lines; drop opener/boundary lines; do not require full-file scan |
| Code cells | Omitted from buffer extract (non-goal: emit as fences) |
| Block comments | Out of scope (`'''`, `/* */`) |
| TDD | Strict fine-grained RED -> GREEN -> refactor; no prod code without a failing test |
| Deps | Stdlib Lua + existing project code only; no new Neovim plugins |

## Target shape

```
lua/gfm_preview/
  percent.lua          -- NEW pure string API (unit-tested heavily)
  source.lua           -- resolve filetype/commentstring; call percent
  init.lua             -- preview_buffer / preview_selection use prepared text
tests/
  percent_spec.lua     -- NEW pure unit tests (majority of coverage)
  source_spec.lua      -- extend: buffer/selection + filetype wiring
  api_spec.lua         -- extend: end-to-end non-md buffer path (mocked pandoc ok)
  fixtures/
    percent_python.py  -- NEW reference fixture from issue
```

Public pure surface (sketch):

```lua
local percent = require("gfm_preview.percent")

percent.is_markdown_filetype(ft)                 -- bool
percent.prefix_for(opts)                         -- "#" | "//" | "--" | ...
percent.uncomment_line(line, prefix)             -- string
percent.is_markdown_opener(line, prefix)         -- bool
percent.is_cell_boundary(line, prefix)           -- bool  (any `# %%...`)
percent.extract_buffer(text, prefix)             -- all md cells joined, or original if none
percent.prepare_selection(text, prefix)          -- uncomment lines; drop openers/boundaries
percent.prepare(text, opts)                      -- dispatch: md ft -> identity; else mode
```

`opts` sketch:

```lua
{
  filetype = "python",          -- vim.bo.filetype
  commentstring = "# %s",       -- vim.bo.commentstring (optional fallback)
  prefix = nil,                 -- explicit override for tests
  mode = "buffer" | "selection",
}
```

Wiring sketch:

```lua
-- source.lua
function M.buffer_markdown()
  return percent.prepare(M.buffer_text(), {
    filetype = vim.bo.filetype,
    commentstring = vim.bo.commentstring,
    mode = "buffer",
  })
end

function M.selection_markdown()
  local text = M.selection_only()
  if not text then return nil end
  return percent.prepare(text, {
    filetype = vim.bo.filetype,
    commentstring = vim.bo.commentstring,
    mode = "selection",
  })
end

-- init.lua
function M.preview_buffer(opts)
  return M.preview(source.buffer_markdown(), opts)
end

function M.preview_selection(opts)
  local text = source.selection_markdown()
  if not text then
    vim.notify("No text selected", vim.log.levels.WARN)
    return nil
  end
  return M.preview(text, opts)
end
```

`M.preview(md_text)` stays a pure "already markdown" entry point (no silent
re-extraction), so unit/API tests that pass raw markdown keep working.

## Prefix resolution

Order:

1. Explicit `opts.prefix` if set (tests).
2. Else filetype table (authoritative for known langs):

   | filetype | prefix |
   |----------|--------|
   | `python`, `r`, `julia`, `ruby`, `perl`, `yaml`, `toml`, `sh`, `bash`, `zsh`, `conf` | `#` |
   | `javascript`, `typescript`, `javascriptreact`, `typescriptreact`, `java`, `c`, `cpp`, `rust`, `go`, `csharp` | `//` |
   | `lua`, `sql`, `haskell` | `--` |

3. Else parse `commentstring`: take the literal before `%s`, trim trailing spaces
   from that piece so `"# %s"` / `"// %s"` / `"-- %s"` yield `#` / `//` / `--`.
4. Else default `#`.

Markdown filetypes (identity path, never strip):

`markdown`, `markdown.pandoc`, `md`, `rmd`, `quarto` (and empty ft only if
buffer name ends with `.md`/`.markdown` - optional; default empty ft = non-md
passthrough via extract which no-ops without openers).

Keep the list small; extend only when a test demands it.

## Uncomment / cell grammar (normative)

### `uncomment_line(line, prefix)`

Exact jupytext semantics (no regex over-strip):

```
prefix_and_space = prefix .. " "
if line starts with prefix_and_space -> drop len(prefix)+1 chars
else if line starts with prefix       -> drop len(prefix) chars
else                                  -> return line
```

Not done: strip all whitespace; strip indentation before the comment marker;
handle block comments.

### Markdown opener

A line is a markdown cell opener iff (after no indent support in v1):

```
^ <prefix> \s* %% \s* \[markdown\]  (.*)? $
```

Examples that match:

- `# %% [markdown]`
- `# %% [markdown] lang=en`
- `#%% [markdown]` (no space after prefix - still opener; content lines still use uncomment)
- `// %% [markdown] key=value`

Examples that do **not** match:

- `# %%` (code cell)
- `# %% [md]` (not the literal `markdown` token)
- `# %% [raw]`
- `## %% [markdown]` (heading-ish; prefix match would need exact prefix at BOL)

BOL only for v1 (no leading whitespace on opener/boundary). Add indented
openers only if a failing real-world fixture appears later.

### Cell boundary (ends previous cell)

```
^ <prefix> \s* %% \b
```

So `# %%`, `# %% [markdown]`, `# %% [raw] foo` all start a new cell and close
the previous one. The boundary line itself is never markdown body content.

### `extract_buffer(text, prefix)`

```
cells = []
current = nil   -- nil | list of body lines

for each line in splitlines(text):  -- keep empty lines; preserve no CR
  if is_markdown_opener(line, prefix):
    flush current into cells if non-nil
    current = []                  -- start new md cell; opener discarded
  elif is_cell_boundary(line, prefix):
    flush current into cells if non-nil
    current = nil                 -- code/raw cell; skip body
  elif current ~= nil:
    append uncomment_line(line, prefix) to current
  else
    skip                           -- outside md cell (code, header, etc.)

flush current
if #cells == 0: return original text
return table.concat(cells, "\n\n")  -- each cell = table.concat(lines, "\n")
```

Trailing newline policy: if original text ends with `\n` and output is non-empty,
end output with `\n` (match `source.buffer_text` friendliness). Prefer locking
this with one explicit test rather than guessing in impl first.

### `prepare_selection(text, prefix)`

Selection is already a slice; do not require surrounding cell context:

```
out = []
for each line:
  if is_markdown_opener(line, prefix) or is_cell_boundary(line, prefix):
    skip
  else
    append uncomment_line(line, prefix)
return table.concat(out, "\n")
```

If every line was skipped -> empty string (caller may still preview empty;
prefer notify only when selection_only was nil - keep current empty-selection
behavior). Lock with a test: selection that is only an opener yields `""`.

For markdown filetypes, `prepare` returns selection text unchanged (no uncomment).

## Strict TDD rules

1. **No production code without a failing test** for that behavior.
2. One behavior per cycle: write test -> `make test-file FILE=...` RED -> minimal
   impl GREEN -> quick refactor if needed -> next.
3. Pure unit tests first (`percent_spec.lua`). Neovim buffer/API tests only after
   pure core is green.
4. Prefer `assert.are.equal` on full strings for pure transforms (mermaid style).
5. Do not expand scope mid-cycle (no ipynb, no code-cell fences, no block comments).
6. Run full `make test` before marking the issue done (no regressions).

Suggested command loop:

```sh
make test-file FILE=tests/percent_spec.lua
make test-file FILE=tests/source_spec.lua
make test-file FILE=tests/api_spec.lua
make test
```

---

## Implementation phases (each step = its own RED/GREEN loop)

### Phase 0 - Spec scaffold (RED harness)

**Test first**

- Create `tests/percent_spec.lua` with `describe("percent", ...)` and a single
  pending-style identity test that `require("gfm_preview.percent")` succeeds.

**GREEN**

- Add `lua/gfm_preview/percent.lua` returning `{}`.

**Done when:** `make test-file FILE=tests/percent_spec.lua` loads the module.

---

### Phase 1 - `uncomment_line` (pure)

**Tests (one `it` per row, or a single parameterized-style list with clear names)**

| name | line | prefix | expected |
|------|------|--------|----------|
| strips hash+space | `# # Title` | `#` | `# Title` |
| strips bare hash blank | `#` | `#` | `""` |
| strips hash+space blank | `# ` | `#` | `""` |
| keeps two-space md indent | `#   marked` | `#` | `  marked` |
| keeps nested list indent | `#     - item` | `#` | `    - item` |
| keeps fence body indent | `#         code` | `#` | `        code` |
| leaves non-comment line | `print(1)` | `#` | `print(1)` |
| strips slash-slash+space | `// ## Hi` | `//` | `## Hi` |
| strips bare slash-slash | `//` | `//` | `""` |
| strips dash-dash+space | `-- ## Hi` | `--` | `## Hi` |
| does not strip longer prefix decoy | `### head` with prefix `#` | `#` | `## head` (only one `#`) |

Note on last row: jupytext strips one prefix occurrence only via `startswith`;
`### head` starts with `#` so becomes `## head`. Document and test that - do not
special-case markdown headings inside the uncomment helper.

**GREEN:** implement `M.uncomment_line`.

**Refactor:** none expected beyond local locals.

---

### Phase 2 - Opener and boundary detectors (pure)

**Tests - `is_markdown_opener`**

- `# %% [markdown]` -> true
- `# %% [markdown] lang=en` -> true
- `# %% [markdown] key=value more=1` -> true
- `#%% [markdown]` -> true (optional spaces after prefix)
- `# %% [markdown]  ` trailing spaces -> true
- `// %% [markdown]` with prefix `//` -> true
- `-- %% [markdown]` with prefix `--` -> true
- `# %%` -> false
- `# %% [raw]` -> false
- `# %% [md]` -> false
- `print("# %% [markdown]")` -> false
- `` -> false
- markdown-looking body `# ## Title` -> false

**Tests - `is_cell_boundary`**

- `# %%` -> true
- `# %% [markdown]` -> true
- `# %% [raw]` -> true
- `# %%foo` -> false (no boundary token; `\b` after `%%`)
- `# % %` -> false
- `// %%` with `//` -> true
- body line `# code` -> false
- `` -> false

**GREEN:** implement both detectors with Lua-safe patterns (remember: Lua
patterns have no `|`; escape magic chars in prefix via a tiny `literal_pat`
helper if needed). Multi-char prefixes (`//`, `--`) must be matched literally.

**Refactor:** shared `function line_after_prefix(line, prefix)` if it clarifies.

---

### Phase 3 - `extract_buffer` single cell (pure)

**Tests**

1. **Simple python cell**

Input:

```text
# %% [markdown]
# # Hello
#
# Body.
```

Expected:

```text
# Hello

Body.
```

(Lock trailing newline in the test once; be consistent thereafter.)

2. **Opener with params dropped**

```text
# %% [markdown] lang=en
# Second cell.
```

-> `Second cell.`

3. **Fenced code inside cell**

```text
# %% [markdown]
# ```python
# print(1)
# ```
```

-> 

```text
```python
print(1)
```
```

4. **Nested list indentation preserved**

```text
# %% [markdown]
# - outer
#   - inner
```

->

```text
- outer
  - inner
```

5. **Math preserved**

```text
# %% [markdown]
# Inline $x$ and
# $$
# y=1
# $$
```

uncommented math source unchanged structurally.

**GREEN:** implement scan loop for a single open cell to EOF.

---

### Phase 4 - `extract_buffer` multi-cell, code cells, passthrough (pure)

**Tests**

1. **Code cell omitted between markdown cells** (issue fixture essence)

```text
# %% [markdown]
# # Hello
#
# Inline $x$ and a fence:
#
# ```python
# print(1)
# ```

# %%
print("code cell ignored by default")

# %% [markdown] lang=en
# Second cell.
```

Expected:

```text
# Hello

Inline $x$ and a fence:

```python
print(1)
```

Second cell.
```

Join rule: exactly one blank line between flushed cells (even if source had more
blank lines between cells).

2. **Leading jupytext header ignored**

```text
# ---
# jupyter:
#   jupytext:
#     format_name: percent
# ---
#
# %% [markdown]
# Hi
```

-> `Hi`  (header lines are outside any md cell)

3. **Only code cells / no markdown cells -> original text identity**

```text
# %%
print(1)
```

-> identical to input (including newlines)

4. **Empty string -> empty string**

5. **Non-`#` prefix extract** (`//`)

```text
// %% [markdown]
// ## Title
//
// para
```

->

```text
## Title

para
```

6. **Mixed: markdown then code then EOF without final newline** - lock exact output.

**GREEN:** complete `extract_buffer`.

**Refactor:** small helpers `flush()`, `split_lines()` that do not drop trailing
empty line information incorrectly. Prefer a tested split that matches
`vim.split(text, "\n", { plain = true })` semantics or pure Lua equivalent used
consistently.

---

### Phase 5 - `prepare_selection` (pure)

**Tests**

1. Body lines only -> uncommented:

```text
# ## Title
# para
```
->
```text
## Title
para
```

2. Selection including opener -> opener dropped:

```text
# %% [markdown]
# ## Title
```
->
```text
## Title
```

3. Selection including code boundary line -> boundary dropped, body uncommented:

```text
# %%
# not actually code in selection path
```
->
```text
not actually code in selection path
```

(Selection path intentionally dumb: uncomment everything that is not a
boundary/opener. Document in code comment - buffer path is the smart extractor.)

4. Indentation preserved after uncomment (same as phase 1 cases on multi-line).

5. `//` prefix selection.

6. Only opener selected -> `""`.

**GREEN:** implement `prepare_selection`.

---

### Phase 6 - `is_markdown_filetype` + `prefix_for` + `prepare` dispatch (pure)

**Tests - filetype**

- `markdown`, `markdown.pandoc`, `rmd`, `quarto` -> true
- `python`, `lua`, `javascript`, `""`, `nil` -> false

**Tests - prefix_for**

- `{ prefix = "!" }` -> `!`
- `{ filetype = "python" }` -> `#`
- `{ filetype = "javascript" }` -> `//`
- `{ filetype = "lua" }` -> `--`
- `{ filetype = "unknownlang", commentstring = "# %s" }` -> `#`
- `{ filetype = "unknownlang", commentstring = "// %s" }` -> `//`
- `{ filetype = "unknownlang", commentstring = "--%s" }` -> `--`
- `{ filetype = "unknownlang" }` -> `#` default

**Tests - prepare**

- md filetype + buffer mode + raw md text -> identity (even if text contains `# %% [markdown]`)
- python + buffer mode + percent fixture -> extracted
- python + buffer mode + no cells -> identity
- python + selection mode + commented body -> uncommented
- markdown + selection mode + `# looks like comment` -> identity (do not strip)

**GREEN:** implement dispatch in `prepare`.

---

### Phase 7 - Wire `source.lua` (buffer tests)

**Tests in `tests/source_spec.lua`** (extend; keep existing green)

1. `buffer_markdown` on `filetype=markdown` returns full buffer text unchanged.
2. `buffer_markdown` on `filetype=python` with percent cells returns extracted md.
3. `buffer_markdown` on `filetype=python` with plain code (no cells) returns original.
4. `selection_markdown` returns nil when no selection (same as selection_only).
5. `selection_markdown` on python strips comment leaders for the visual range.
6. `selection_markdown` on markdown does not strip.

Use existing mark helpers from `source_spec.lua`. Set `vim.bo.filetype` in each
test. Prefer not to rely on `commentstring` if filetype is in the table.

**GREEN:** add `M.buffer_markdown` / `M.selection_markdown` calling `percent.prepare`.

Do **not** change `buffer_text` / `selection_only` semantics (other callers/tests
depend on raw text).

---

### Phase 8 - Wire `init.lua` preview entry points

**Tests in `tests/api_spec.lua`**

1. `preview_buffer` with `filetype=python` and percent markdown cell, mocked
   pandoc: assert the markdown file written for pandoc contains uncommented
   heading (e.g. matches `^# Hello` or `Hello` without leading `# %%`).
2. `preview_buffer` with `filetype=markdown` still previews raw buffer (existing
   behavior preserved; can be a thin regression).
3. `preview_selection` on python selection strips leaders before pandoc (mocked).
4. Direct `preview("# %% [markdown]\n# x\n")` does **not** auto-extract (raw path
   unchanged) - locks the "preview expects markdown" contract.

Pattern for reading pandoc input: same as existing mocked pandoc tests (open
`argv` md path). Adjust argv index carefully; prefer scanning argv for the
`.md` input path rather than hard-coding index if fragile.

**GREEN:** switch `preview_buffer` / `preview_selection` to `buffer_markdown` /
`selection_markdown`. Leave `preview_annotation` as-is (annotation bodies are
already markdown).

---

### Phase 9 - Fixture file + optional live integration

**Add** `tests/fixtures/percent_python.py` exactly as in the issue (plus final
newline).

**Pure test** (in `percent_spec.lua`): read fixture from disk, extract with
prefix `#`, `assert.are.equal` against the expected markdown string (golden).

**Optional live test** (in `integration_spec.lua` or `api_spec.lua`, pending if
no pandoc): extract fixture -> `gfm.preview(extracted, { open_browser=false })`
-> HTML contains `<h1` and `print`. Keep optional so CI without pandoc still
passes unit suite.

**GREEN:** fixture on disk; golden test green.

---

### Phase 10 - README + issue AC sweep

**Docs**

- README "Supported markdown" or new "Percent-format source files" bullet:
  non-md buffers with `# %% [markdown]` (jupytext percent) are extracted and
  uncommented before preview.
- Mention selection behavior briefly.
- Non-goals stay out of README feature list.

**Manual AC checklist** (tick in issue when done):

- [ ] Python jupytext percent cells render as GFM
- [ ] Openers with/without params dropped
- [ ] prefix + at most one space; deeper spaces kept
- [ ] Multi-cell concat order
- [ ] Code cells omitted
- [ ] Markdown ft unaffected
- [ ] Non-`#` prefix (`//` or `--`) covered by tests
- [ ] Selection strips leaders
- [ ] Unit tests listed in issue present

**Final gate:** `make test` full green.

---

## Explicit non-goals (do not implement under this plan)

- `.ipynb` / full jupytext round-trip
- Executing code cells
- Emitting code cells as fenced blocks in buffer preview
- Block comment carriers
- Indented openers / cell boundaries with leading whitespace
- Spyder/VS Code cell folding UI
- Changing preprocess order, pandoc argv, assets, or browser behavior
- New user commands or config knobs (no `setup()` option required for v1)

If a config flag is requested later (`percent = true/false`), that is a follow-up
issue; default-on for non-md is enough here.

---

## Risk notes / Lua pitfalls

- Lua patterns: no alternation `|`; `-`, `*`, `+`, `?`, `%` are magic. Build
  opener/boundary patterns by concatenating a plain-escaped prefix.
- Multi-char prefix: `startswith` style via `line:sub(1, #prefix) == prefix`
  (same as jupytext) is simpler and safer than patterns for `uncomment_line`.
- Do not use `line:gsub("^#+", ...)` - over-strips headings after uncomment.
- `table.concat` default separator is empty; always pass `"\n"`.
- Trailing newline / final empty line: define via tests before "fixing" split.
- `vim.split` vs pure split: pick one in percent.lua; pure Lua preferred so
  tests do not depend on nvim (they run in nvim anyway, but purity keeps the
  module portable and simple).
- Avoid changing `source.buffer_or_visual` unless a test forces it; new APIs
  keep the blast radius small.

---

## Suggested first session (when you say go)

1. Phase 0 scaffold + Phase 1 `uncomment_line` full RED/GREEN.
2. Phase 2 detectors RED/GREEN.
3. Stop after Phase 2 if you want a review checkpoint; otherwise continue
   through Phase 4 (core extract) in the same session.

Do not start Phase 7 wiring until Phases 1-6 pure core is green.

---

## Progress checklist

| Phase | Status | Notes |
|-------|--------|-------|
| 0 scaffold | done | `tests/percent_spec.lua` + module shell |
| 1 uncomment_line | done | 13 unit cases |
| 2 opener/boundary | done | 21 unit cases |
| 3 extract single cell | done | 6 unit cases incl. trailing-newline policy |
| 4 extract multi/code/pass | done | 6 more; flush trims trailing blanks |
| 5 prepare_selection | done | 6 unit cases |
| 6 prepare dispatch | done | filetype/prefix/prepare covered |
| 7 source wiring | done | buffer_markdown/selection_markdown + 6 spec cases |
| 8 init/API wiring | done | preview_buffer/selection use prepared text; 4 API cases |
| 9 fixture + golden | done | `tests/fixtures/percent_python.py` golden |
| 10 README + full test | done | README bullet added; `make test` all green |
