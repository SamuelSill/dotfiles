-- config/git.lua -- git blame / line history / hunk staging (gitsigns + fugitive)
-- and merge-conflict navigation & resolution (git-conflict.nvim).

local map = vim.keymap.set

local function selected_range()
  local s, e = vim.fn.line('v'), vim.fn.line('.')
  if s > e then s, e = e, s end
  return s, e
end

map('n', '<leader>gb', function() require('gitsigns').blame_line({ full = true }) end,
  { desc = 'Blame line (popup)' })
map('n', '<leader>gB', function() require('gitsigns').toggle_current_line_blame() end,
  { desc = 'Toggle inline blame' })
map('n', '<leader>gv', '<cmd>Git blame<cr>', { desc = 'Blame column (side-by-side)' })

map('n', '<leader>gl', function()
  local l = vim.fn.line('.')
  vim.cmd(string.format('Git log -L %d,%d:%%', l, l))
end, { desc = 'Line history' })
map('x', '<leader>gl', function()
  local s, e = selected_range()
  vim.cmd(string.format('Git log -L %d,%d:%%', s, e))
end, { desc = 'Line history (selection)' })

-- Working-tree diff if the line sits in an uncommitted hunk, else blame the
-- commit that last touched it (<leader>gb only ever does the latter).
map('n', '<leader>gc', function()
  local gs = require('gitsigns')
  local lnum = vim.fn.line('.')
  for _, h in ipairs(gs.get_hunks() or {}) do
    local first = h.added.start
    local last = first + math.max(h.added.count, 1) - 1  -- pure deletion anchors on its start line
    if lnum >= first and lnum <= last then
      gs.preview_hunk()
      return
    end
  end
  gs.blame_line({ full = true })
end, { desc = 'Last change on line (working tree or last commit)' })

-- reset_hunk with a {first,last} range scopes the reset to those lines only,
-- not the whole hunk.
map('n', '<leader>gr', function()
  local l = vim.fn.line('.')
  require('gitsigns').reset_hunk({ l, l })
end, { desc = 'Restore line (discard changes)' })
map('x', '<leader>gr', function()
  require('gitsigns').reset_hunk({ selected_range() })
end, { desc = 'Restore lines (discard changes)' })

map('n', '<leader>gs', function()
  require('gitsigns').stage_hunk()
end, { desc = 'Stage hunk under cursor' })
map('x', '<leader>gs', function()
  require('gitsigns').stage_hunk({ selected_range() })
end, { desc = 'Stage selected lines' })

map('n', ']x', '<cmd>GitConflictNextConflict<cr>', { desc = 'Next git conflict' })
map('n', '[x', '<cmd>GitConflictPrevConflict<cr>', { desc = 'Prev git conflict' })
map('n', '<leader>gxo', '<cmd>GitConflictChooseOurs<cr>',   { desc = 'Conflict: choose ours (current)' })
map('n', '<leader>gxt', '<cmd>GitConflictChooseTheirs<cr>', { desc = 'Conflict: choose theirs (incoming)' })
map('n', '<leader>gxb', '<cmd>GitConflictChooseBoth<cr>',   { desc = 'Conflict: choose both' })
map('n', '<leader>gxn', '<cmd>GitConflictChooseNone<cr>',   { desc = 'Conflict: choose none' })
