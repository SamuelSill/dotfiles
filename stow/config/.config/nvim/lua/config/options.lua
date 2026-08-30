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
opt.shada:prepend("'1000")
opt.shada:remove("'100")
opt.splitright = true
opt.splitbelow = true
opt.cursorline = true
opt.wrap = true
opt.linebreak = true
opt.breakindent = true
-- Indentation width (expandtab/shiftwidth/tabstop) intentionally left at Neovim
-- defaults here; project-specific styles come from a local override.

-- Ruler just past the textwidth=72 that runtime/ftplugin/gitcommit.vim sets, so it
-- marks exactly where a commit message auto-wraps. Drawn as a virtual-text glyph
-- rather than colorcolumn, which fills its whole cell and reads as a wide bar.
local commit_ruler_namespace = vim.api.nvim_create_namespace('commit_message_ruler')
local commit_ruler_column = 72   -- 0-based, so the glyph lands on column 73

local function draw_commit_ruler(buffer)
  vim.api.nvim_buf_clear_namespace(buffer, commit_ruler_namespace, 0, -1)
  for line = 0, vim.api.nvim_buf_line_count(buffer) - 1 do
    vim.api.nvim_buf_set_extmark(buffer, commit_ruler_namespace, line, 0, {
      virt_text = { { '│', 'CommitMessageRuler' } },
      virt_text_win_col = commit_ruler_column,
      hl_mode = 'combine',
    })
  end
end

local commit_ruler_group = vim.api.nvim_create_augroup('commit_message_ruler', { clear = true })

vim.api.nvim_create_autocmd('FileType', {
  group = commit_ruler_group,
  pattern = 'gitcommit',
  callback = function(args)
    -- Re-set on every commit buffer, so a colorscheme load that clears the group
    -- doesn't leave the ruler unstyled.
    vim.api.nvim_set_hl(0, 'CommitMessageRuler', { fg = '#bf00ff' })
    draw_commit_ruler(args.buf)
    vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
      group = commit_ruler_group,
      buffer = args.buf,
      callback = function() draw_commit_ruler(args.buf) end,
    })
  end,
})

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
