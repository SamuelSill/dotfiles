-- config/topbar.lua -- the always-on shortcut bar + the :Reload command.

-- The topbar plugin is a git submodule at DOTFILES_DIR/topbar, loaded off
-- runtimepath rather than symlinked into ~/.config. Mirrors init.lua's fallback.
local DOTFILES_DIR = vim.env.DOTFILES_DIR
if not DOTFILES_DIR or DOTFILES_DIR == '' then
  DOTFILES_DIR = vim.fn.expand('~/dotfiles')
end

-- topbar forces laststatus=3 (one global statusline): a reserved top window under
-- laststatus=2 would draw its own statusline as an extra row. lualine is set to
-- globalstatus=true (config/plugins.lua) to match. The general JSON layout is
-- merged with an optional machine-specific one ($NVIM_LOCAL_TOPBAR).
local topbar_dir = DOTFILES_DIR .. '/topbar'
if vim.fn.isdirectory(topbar_dir) == 1 then
  vim.opt.runtimepath:append(topbar_dir)
  -- The stow-symlinked file next to this init; fall back to the repo copy for a
  -- non-stowed / standalone checkout.
  local general_json = vim.fn.stdpath('config') .. '/topbar.json'
  if not (vim.uv or vim.loop).fs_stat(general_json) then
    general_json = DOTFILES_DIR .. '/stow/config/.config/nvim/topbar.json'
  end
  local topbar_configs = { general_json }
  local local_topbar = vim.env.NVIM_LOCAL_TOPBAR
  if local_topbar and local_topbar ~= '' and (vim.uv or vim.loop).fs_stat(local_topbar) then
    table.insert(topbar_configs, local_topbar)
  end
  require('topbar').setup({ configs = topbar_configs })
end

vim.api.nvim_create_user_command('Reload', function()
  local rc = vim.env.MYVIMRC
  if not rc or rc == '' then rc = vim.fn.stdpath('config') .. '/init.lua' end
  vim.cmd('source ' .. vim.fn.fnameescape(rc))
  pcall(vim.cmd, 'TopbarReload')
  -- Re-sourcing recreates windows, so fzf-lua's cached context can point at a
  -- now-dead window id -- clear it so the next gd/gr recaptures.
  pcall(function() require('fzf-lua.utils').clear_CTX() end)
  vim.notify('Reloaded config + topbar')
end, { desc = 'Reload init.lua and the topbar' })
