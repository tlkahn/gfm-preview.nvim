-- Minimal Neovim init for running plenary.busted specs headlessly.
-- Adds the plugin root and plenary.nvim to the runtimepath, then loads busted.

local src = debug.getinfo(1, "S").source
local tests_dir = vim.fn.fnamemodify(src:sub(2), ":p:h")
local plugin_root = vim.fn.fnamemodify(tests_dir, ":h")

vim.opt.runtimepath:prepend(plugin_root)
vim.opt.runtimepath:append(vim.fn.stdpath("data") .. "/lazy/plenary.nvim")

require("plenary.busted")
