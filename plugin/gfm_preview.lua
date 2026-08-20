-- gfm_preview plugin entry: user commands.
-- Keymaps are installed by require("gfm_preview").setup().

local gfm = require("gfm_preview")

vim.api.nvim_create_user_command("GfmPreview", function()
  gfm.preview_buffer()
end, { desc = "GfmPreview: preview the whole buffer", range = true })

vim.api.nvim_create_user_command("GfmPreviewSelection", function()
  gfm.preview_selection()
end, { desc = "GfmPreview: preview the current selection only", range = true })

vim.api.nvim_create_user_command("GfmPreviewAnnotation", function()
  gfm.preview_annotation()
end, { desc = "GfmPreview: preview a Lit annotation body" })
