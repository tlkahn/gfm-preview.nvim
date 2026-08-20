# Plan: Issue #3 - Visual `<leader>mp` selection preview no-ops or shows stale selection

Track: https://github.com/tlkahn/gfm-preview.nvim/issues/3

## Goal

Make visual-mode selection preview always render the **currently active**
visual selection, never a stale one, and always give the `"No text selected"`
warning when no selection can be resolved.

## Root cause (verified empirically, nvim 0.12 headless)

The visual keymap callback runs **while still in visual mode**. At that point
`'<` / `'>` still hold the *previous* selection (or nothing at all on a fresh
buffer). Reproduced:

```
pre marks        '< = {0,1,1,0}   '> = {0,1,10,0}     -- old selection, line 1
normal! 3G V                                          -- new live selection, line 3
in callback:     mode() == "V"
                 getpos("v") = {0,3,1,0}  getpos(".") = {0,3,1,0}   -- LIVE
                 getpos("'<") = {0,1,1,0} getpos("'>") = {0,1,10,0} -- STALE
LIVE  capture -> "gamma line"     (correct)
MARKS capture -> "alpha line"     (what the plugin currently previews)
```

This explains both symptoms:

- **Symptom B (stale preview):** marks point at the previous selection.
- **Symptom A (no-op):** on a buffer with no prior visual selection the marks
  are unset (`lnum == 0`) or equal -> `selection_markdown()` returns nil ->
  only a WARN notify (easy to miss); no browser.

Secondary defect (same code path): `:GfmPreviewSelection` is defined without
`range = true`, so typing `:` from visual mode auto-inserts `'<,'>` and the
command **errors with E481** - another silent-looking no-op.

Latent defects in the byte-slicing fallback (fixed for free by `getregion()`):

- linewise `'>` column is `v:maxcol` (huge) - `:sub(1, end_col)` only works by
  accident;
- multibyte text: `getpos` columns are byte-based but the code assumes they
  align with character ends (`:sub` is fine for bytes, but inclusive-end
  charwise selections over multibyte chars cut mid-character);
- blockwise selections are silently treated as charwise.

## Decisions locked in

| Topic | Choice |
|-------|--------|
| Capture API | `vim.fn.getregion(start, end, {type = ...})` (nvim >= 0.10; user runs 0.12) |
| Live path | In visual mode: `getpos("v")` + `getpos(".")`, type = `mode()` |
| Fallback path | Not in visual mode: `'<` / `'>` marks, type = `visualmode()` or `"v"` when empty |
| Empty detection (live) | `getregion()` result empty, or all-empty strings -> nil |
| Empty detection (marks) | Keep legacy guard: unset marks (`lnum == 0`) or identical start/end -> nil (preserves existing spec semantics) |
| Blockwise | Supported; lines joined with `"\n"` (getregion returns the rectangle rows) |
| Keymap UX | After capturing in the visual callback, leave visual mode (`<Esc>` via `nvim_feedkeys`) so the mapping visibly "completes" |
| `:GfmPreviewSelection` | Add `range = true` so `:'<,'>GfmPreviewSelection` works; command still reads marks (they ARE updated once `:` is pressed) |
| `:GfmPreview` | Also gets `range = true` (harmless; avoids E481 from visual `:`) |
| No-selection feedback | Keep single notify point in `preview_selection()`; add test that the visual keymap path reaches it |
| Old byte-slicing code | Deleted, replaced by `getregion`-based capture (both paths) |
| Requirements | README notes nvim >= 0.10 |
| TDD | Strict fine-grained RED -> GREEN -> refactor; no prod code without a failing test |
| Deps | Stdlib + built-in Neovim API only; no new plugins |

## Target shape

```
lua/gfm_preview/
  source.lua           -- CHANGED: mode-aware visual_selection() via getregion
  init.lua             -- CHANGED: visual keymap exits visual mode after capture
plugin/gfm_preview.lua -- CHANGED: range = true on GfmPreview/GfmPreviewSelection
tests/
  source_spec.lua      -- EXTENDED: live visual capture, stale-mark regression,
                       --           linewise/blockwise/multibyte, empty cases
  api_spec.lua         -- EXTENDED: preview_selection from live visual mode
  plugin_spec.lua      -- EXTENDED: '<,'>GfmPreviewSelection accepts a range
README.md              -- nvim >= 0.10 requirement note
```

Public surface change (source.lua): none - `selection_only()`,
`buffer_or_visual()`, `selection_markdown()` keep their signatures; only the
internal `visual_selection()` is rewritten:

```lua
local VISUAL_MODES = { v = true, V = true, ["\22"] = true }

local function visual_selection()
  local mode = vim.fn.mode()
  if VISUAL_MODES[mode] then
    -- LIVE: called from a visual-mode mapping; marks are stale here.
    local region = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = mode })
    local text = table.concat(region, "\n")
    if text == "" then return nil end
    return text
  end
  -- FALLBACK: after leaving visual mode (:GfmPreviewSelection, API callers).
  local start_pos, end_pos = vim.fn.getpos("'<"), vim.fn.getpos("'>")
  if start_pos[2] == 0 or end_pos[2] == 0 then return nil end
  if start_pos[2] == end_pos[2] and start_pos[3] == end_pos[3] then return nil end
  local vtype = vim.fn.visualmode()
  if vtype == "" then vtype = "v" end
  local region = vim.fn.getregion(start_pos, end_pos, { type = vtype })
  local text = table.concat(region, "\n")
  if text == "" then return nil end
  return text
end
```

Keymap change (init.lua):

```lua
vim.keymap.set("v", cfg.keymap, function()
  M.preview_selection()
  -- leave visual mode so the mapping visibly completes
  local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
  vim.api.nvim_feedkeys(esc, "n", false)
end, { desc = "GfmPreview: preview selection" })
```

Command change (plugin/gfm_preview.lua):

```lua
vim.api.nvim_create_user_command("GfmPreviewSelection", function()
  gfm.preview_selection()
end, { desc = "...", range = true })
-- same for GfmPreview
```

## Test-environment notes (validated before writing this plan)

- Inside a headless lua context, `vim.cmd("normal! vj")` enters and **stays**
  in visual mode for the rest of the same callback - so specs can enter visual
  mode, call `source.selection_only()`, assert, then clean up with
  `vim.cmd("normal! \27")` (`\27` = `<Esc>`).
- `vim.fn.getregion(getpos("v"), getpos("."), {type = mode()})` returns the
  live selection; `'<`/`'>` remain stale until visual mode is left. This is
  the exact discrepancy the RED regression test locks down.
- `nvim_buf_set_mark` cols are 0-based; `getpos` cols are 1-based (existing
  specs already handle this).
- Existing mark-based specs in `source_spec.lua` / `api_spec.lua` must stay
  green: the mark fallback keeps the "unset or identical marks -> nil"
  semantics. `visualmode()` is `""` in fresh test buffers, hence the `"v"`
  type fallback.
- Every spec that enters visual mode MUST `<Esc>` in the same test (or in an
  `after_each`) so later tests are not polluted by leftover visual state or
  updated marks.

## Strict TDD rules

1. **No production code without a failing test** for that behavior.
2. One behavior per cycle: write test -> `make test-file FILE=...` RED ->
   minimal impl GREEN -> quick refactor -> next.
3. Phase 0 regression test must be RED against current `main` before any fix.
4. Full `make test` before marking the issue done (no regressions in the
   percent/annotation paths that share `visual_selection`).

Command loop:

```sh
make test-file FILE=tests/source_spec.lua
make test-file FILE=tests/api_spec.lua
make test-file FILE=tests/plugin_spec.lua
make test
```

---

## Implementation phases (each step = its own RED/GREEN loop)

### Phase 0 - Regression harness: stale-mark bug reproduced (RED)

**Test first** (`tests/source_spec.lua`, new `describe("live visual capture")`)

1. `selection_only returns the LIVE visual selection, not stale marks`:
   - buffer `{ "alpha line", "beta line", "gamma line" }`
   - set stale marks on line 1 (`nvim_buf_set_mark "<"/">"`)
   - `nvim_win_set_cursor {3,1}` + `vim.cmd("normal! V")`
   - expect `source.selection_only() == "gamma line"`
   - cleanup `vim.cmd("normal! \27")`

**RED:** current code returns `"alpha line"` (stale marks). Confirm RED before
touching prod code.

**GREEN:** implement the live branch of `visual_selection()` (mode check +
`getregion`), keep the old mark code path untouched for now.

---

### Phase 1 - Live capture matrix (charwise / linewise / blockwise / multibyte)

**Tests (one `it` each; all enter visual with `normal!`, all `<Esc>` cleanup)**

| name | setup | expected |
|------|-------|----------|
| charwise within one line | `normal! 0v3l` on `"abcdef"` | `"abcd"` |
| charwise across lines | cursor 1,1 `normal! vj` on `abcdef/ghijkl` | `"abcdef\ng"` (lock exact getregion output) |
| linewise multi-line | `normal! Vj` from line 2 | `"beta line\ngamma line"` |
| blockwise | `normal! <C-v>jl` (use `"\22"` termcode) | two rectangle rows joined by `"\n"` |
| single-char live selection | `normal! v` (no motion) | that one character (live path allows it) |
| multibyte charwise | line `"héllo wörld"` select over `é` | no mid-character byte cut |

**GREEN:** live branch already exists from Phase 0; these tests pin down
`getregion` typing (`v`/`V`/`\22`) and the `"\n"` join. Fix only what a RED
test forces.

**Refactor:** extract `local function region_text(start, end_, vtype)` shared
by both branches.

---

### Phase 2 - Mark fallback path via getregion

**Tests**

1. `after leaving visual mode, marks give the just-finished selection`:
   `normal! Vj` then `normal! \27`, then `selection_only()` returns the two
   lines (fallback path, `visualmode() == "V"`).
2. `linewise marks do not depend on v:maxcol column math`: same as above but
   assert full final line is present (kills the old `:sub(1, end_col)` hack).
3. Existing specs stay green unchanged:
   - unset marks -> nil,
   - identical marks -> nil (`buffer_or_visual` falls back to buffer),
   - `nvim_buf_set_mark`-seeded charwise selection returns the same text as
     before (`"line two\nline"` case).
4. `visualmode() empty falls back to charwise`: seed marks with
   `nvim_buf_set_mark` only (no real visual mode ever entered in that buffer)
   and expect the legacy charwise result.

**GREEN:** replace the byte-slicing block with `region_text(marks..., vtype)`
plus the legacy empty guards. Delete the manual `:sub` code.

**Refactor:** none expected.

---

### Phase 3 - selection_markdown / percent wiring with live selection

**Tests (`tests/source_spec.lua`)**

1. `selection_markdown strips comment leaders for a LIVE python selection`:
   ft `python`, buffer `{ "# %% [markdown]", "# ## Title", "# para" }`,
   `normal! 2GVj`, expect `"## Title\npara"`, cleanup ft and `<Esc>`.
2. `selection_markdown returns nil when not in visual mode and no marks`
   (already exists - must stay green).

**GREEN:** should already pass via Phases 0-2 (pure wiring). If it passes
immediately, mark the cycle as verified-green (no prod change needed) and move
on - do not invent code.

---

### Phase 4 - API path: preview_selection from live visual mode

**Tests (`tests/api_spec.lua`)**

1. `preview_selection previews the LIVE selection, not stale marks`:
   - stale marks on `"alpha"`, live `normal! V` on `"beta"`,
   - `gfm.preview_selection()` (open_browser = false),
   - HTML contains `beta` and does NOT contain `alpha`.
2. `preview_selection notifies when invoked with no live selection and no
   marks` (exists - stays green).

**GREEN:** no prod change expected; this locks the end-to-end path.

---

### Phase 5 - Keymap leaves visual mode after preview

**Tests (`tests/api_spec.lua` or new `tests/keymap_spec.lua`)**

1. `setup installs a visual-mode mapping`: `vim.fn.maparg(cfg.keymap, "v")`
   is non-empty (cheap sanity, likely already true).
2. `visual callback exits visual mode`: enter visual, invoke the mapping
   callback (`maparg(..., "v", false, true).callback()` with mocked
   pandoc/open_browser=false), flush with `nvim_feedkeys` +
   `vim.api.nvim_eval("mode()")` after a `vim.wait`/`feedkeys("", "x")` drain,
   expect mode `n`.
   - If deterministic mode assertion proves flaky headless, downgrade this
     cycle to: callback calls `nvim_feedkeys` with `<Esc>` (spy on
     `vim.api.nvim_feedkeys`), and note the manual QA step instead. Decide at
     RED time; do not ship an intermittently-failing test.

**GREEN:** add the `<Esc>` feedkeys line to the visual keymap in
`init.lua.setup`.

---

### Phase 6 - `:GfmPreviewSelection` accepts a range (E481 fix)

**Tests (`tests/plugin_spec.lua`)**

1. `GfmPreviewSelection accepts a '<,'> range`:
   - seed marks (or do a real `normal! Vj` + `<Esc>`),
   - mock notify; run `vim.cmd("'<,'>GfmPreviewSelection")` with
     `open_browser = false` and mocked pandoc,
   - expect **no error** (pcall true) and no `E481`.

**RED:** currently throws `E481: No range allowed`.

**GREEN:** add `range = true` to `GfmPreviewSelection` (and `GfmPreview`).

2. `GfmPreview with a range still previews the whole buffer` (documented
   behavior: range is accepted-and-ignored for the buffer command; one test
   locks that it does not error).

---

### Phase 7 - README, issue AC sweep, full suite

**Docs**

- README Requirements: add `Neovim >= 0.10 (vim.fn.getregion)`.
- README Usage: note visual `<leader>mp` previews the live selection and
  exits visual mode; `:'<,'>GfmPreviewSelection` also works.

**Manual QA checklist** (tick in issue #3 before closing):

- [ ] Fresh buffer, first-ever visual selection + `<leader>mp` -> browser opens with that text (symptom A)
- [ ] Select region A, preview, select region B, preview -> B shown, never A (symptom B)
- [ ] Linewise `V` selection previews full lines
- [ ] Blockwise `<C-v>` selection previews the rectangle
- [ ] Multibyte text selection renders without mojibake/cut chars
- [ ] Normal-mode `<leader>mp` still previews the whole buffer
- [ ] `:'<,'>GfmPreviewSelection` from visual mode works without E481
- [ ] No-selection case shows "No text selected" WARN

**Final gate:** `make test` full green; close issue with AC checked.

---

## Explicit non-goals (do not implement under this plan)

- Supporting nvim < 0.10 (no hand-rolled getregion polyfill)
- Select-mode (`s`/`S`) mappings
- Operator-pending / dot-repeat support
- Live-reload of an already-open browser tab (each preview writes fresh HTML;
  browser reuse behavior is the OS opener's business)
- Changing preprocess order, pandoc argv, assets, or browser behavior
- New config knobs

## Risk notes

- `getregion()` signature: positions are `getpos()`-style lists; `type` must
  be `"v"`, `"V"`, or `"\22"` - pass `mode()` / `visualmode()` through, with
  the `""` -> `"v"` fallback for programmatically-seeded marks.
- Charwise `getregion` end-inclusivity may differ by one column from the old
  `:sub` math in edge cases; **the Phase 1 tests define truth** - update
  expected strings from actual getregion output at RED time, then never touch
  the impl to chase old byte math.
- Visual-state leakage between specs: every `normal! v/V/<C-v>` must be paired
  with `normal! \27`. Prefer a `with_visual(keys, fn)` helper in the spec.
- `nvim_feedkeys` in headless tests is queued, not synchronous; Phase 5 test
  needs an explicit drain (`feedkeys("", "x")`) or the spy fallback.
- `buffer_or_visual()` is shared by `annotation_body()`: live-mode capture now
  changes what `:GfmPreviewAnnotation` sees when run from visual mode - this
  is the *desired* consistency, but re-run annotation specs in the full suite.

## Suggested first session

1. Phase 0 regression RED (confirm it fails on current main) -> GREEN.
2. Phase 1 capture matrix, Phase 2 mark fallback.
3. Stop for a review checkpoint; Phases 3-7 in the next session.

## Progress checklist

| Phase | Status | Notes |
|-------|--------|-------|
| 0 stale-mark regression | done | RED confirmed (stale "alpha line") -> live branch GREEN |
| 1 live capture matrix | done | char/line/block/multibyte all green via live branch; region_text extracted |
| 2 mark fallback via getregion | done | legacy guards preserved; byte-slicing deleted; added multibyte seeded-marks RED test (plan's listed tests passed by accident vs old code) |
| 3 selection_markdown wiring | done | verified-green, no prod change needed |
| 4 API live-selection e2e | done | verified-green, no prod change needed |
| 5 keymap exits visual | done | mode-assertion deterministic after feedkeys("", "x") drain; no spy fallback needed |
| 6 command range (E481) | done | range = true on GfmPreview + GfmPreviewSelection |
| 7 README + QA + full suite | done | full suite 219 tests green; manual QA checklist still needs user tick in issue #3 |

Notes from implementation:
- Scratch-buffer isolation per test was required: real linewise visual selections leave the '>' mark col stuck at v:maxcol (neither nvim_buf_set_mark nor setpos can shrink it), and visualmode() is per-buffer, so mark-seeded tests need a fresh buffer.
- Phase 2's listed tests (after-Esc marks, v:maxcol, seeded charwise) all pass against the old byte-slicing code (Lua :sub with a huge index returns to end, and real visual selections leave char-aligned marks); the genuine RED forcing the getregion fallback was seeded multibyte marks (old code returned "éll", getregion "él").
