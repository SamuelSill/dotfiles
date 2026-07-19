-- config/explorer.lua -- nvim-tree breadcrumb winbar.

-- nvim-tree has no true multi-line sticky scroll (upstream issue #2650), so we
-- render the ancestor-folder chain of the node under the cursor into the tree
-- window's winbar to keep it visible while scrolling a deep folder.
local function nvimtree_breadcrumb()
  local ok, api = pcall(require, 'nvim-tree.api')
  if not ok then return end
  local node = api.tree.get_node_under_cursor()
  local parts = {}
  if node and node.absolute_path then
    local rel = vim.fn.fnamemodify(node.absolute_path, ':~:.')
    parts = vim.split(rel, '/', { trimempty = true })
    if node.type ~= 'directory' then table.remove(parts) end
  end
  if #parts == 0 then parts = { vim.fn.fnamemodify(vim.fn.getcwd(), ':t') } end
  vim.wo.winbar = ' %#NvimTreeFolderName#' .. table.concat(parts, '  ')
end

vim.api.nvim_create_autocmd({ 'CursorMoved', 'BufWinEnter' }, {
  callback = function()
    if vim.bo.filetype == 'NvimTree' then nvimtree_breadcrumb() end
  end,
})
