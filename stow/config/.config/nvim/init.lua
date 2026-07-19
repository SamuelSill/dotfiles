-- Neovim entry point (general / shared config, deployed by GNU stow).
--
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- Purge already-loaded config.* modules so re-sourcing this file (what :Reload
-- does) re-runs each one; require() alone would return the cached copy.
for name in pairs(package.loaded) do
  if name:match('^config%.') then package.loaded[name] = nil end
end

require('config.options')
require('config.plugins')
require('config.lsp')
require('config.keymaps')
require('config.git')
require('config.explorer')
require('config.topbar')

-- Machine-specific overrides, loaded last so they win. No-op on a plain checkout.
local local_init = vim.env.NVIM_LOCAL_INIT
if local_init and local_init ~= '' and (vim.uv or vim.loop).fs_stat(local_init) then
  dofile(local_init)
end
