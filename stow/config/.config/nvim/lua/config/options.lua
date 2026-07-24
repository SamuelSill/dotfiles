-- config/options.lua -- editor options + trim-trailing-whitespace on save.

local opt = vim.opt
opt.number = true
opt.relativenumber = true
opt.mouse = 'a'
opt.clipboard = 'unnamedplus'
opt.smartindent = true
opt.ignorecase = true
opt.smartcase = false        -- case-insensitive even when the query has a capital
opt.termguicolors = true
opt.signcolumn = 'yes'        -- always-on gutter, so text doesn't jump on new errors
opt.updatetime = 250
opt.timeoutlen = 350          -- also how long a pause on the leader waits before topbar
opt.scrolloff = 8
opt.undofile = true
opt.splitright = true
opt.splitbelow = true
opt.cursorline = true
opt.wrap = true
opt.linebreak = true
opt.breakindent = true
-- Indentation width (expandtab/shiftwidth/tabstop) intentionally left at Neovim
-- defaults here; project-specific styles come from a local override.

-- Skips diff/patch (stripping would corrupt the file) and markdown (two trailing
-- spaces are a hard line break). winsaveview/winrestview keep cursor+scroll put;
-- keeppatterns avoids stomping the last search.
vim.api.nvim_create_autocmd('BufWritePre', {
  group = vim.api.nvim_create_augroup('trim_trailing_whitespace', { clear = true }),
  callback = function()
    if vim.tbl_contains({ 'diff', 'patch', 'markdown' }, vim.bo.filetype) then return end
    local view = vim.fn.winsaveview()
    vim.cmd([[keeppatterns %s/\s\+$//e]])
    vim.fn.winrestview(view)
  end,
})
