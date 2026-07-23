-- config/lsp.lua -- clangd/LSP setup, the "smart" gd/gr that work in any buffer,
-- and buffer-local LspAttach keymaps. Loaded after config/plugins.lua.
-- Returns the smart goto/references fns so config/keymaps.lua can bind them
-- globally too; also exposed as globals for a machine-specific override to reuse.

local M = {}

local capabilities = require('cmp_nvim_lsp').default_capabilities()

-- Wildcard so completion capabilities reach every server, not just C/C++.
vim.lsp.config('*', { capabilities = capabilities })

-- lspconfig ships clangd's filetypes/root markers; we only set the system-binary
-- cmd on top (a local override swaps in Chromium's).
vim.lsp.config('clangd', { cmd = { 'clangd' } })

-- rust-analyzer runs `cargo check` for its on-save error hints by default; use
-- `cargo clippy` instead so we get clippy's lints.
vim.lsp.config('rust_analyzer', {
  settings = {
    ['rust-analyzer'] = {
      check = {
        command = 'clippy',
      },
    },
  },
})

vim.lsp.enable({ 'clangd', 'pyright', 'rust_analyzer', 'omnisharp' })

-- Re-apply on ColorScheme so the symbol-under-cursor highlight survives a theme switch.
local function set_reference_hl()
  for _, g in ipairs({ 'LspReferenceText', 'LspReferenceRead', 'LspReferenceWrite' }) do
    vim.api.nvim_set_hl(0, g, { link = 'Visual' })
  end
  -- rust-analyzer/clangd tag unused imports & bindings as "unnecessary"; Neovim
  -- renders those via DiagnosticUnnecessary, which most themes make a faint grey
  -- so they end up *less* visible than normal code. Add an undercurl so they read
  -- as flagged, not just dim.
  vim.api.nvim_set_hl(0, 'DiagnosticUnnecessary', { undercurl = true, sp = '#e5c07b' })
end
set_reference_hl()
vim.api.nvim_create_autocmd('ColorScheme', { callback = set_reference_hl })

local function open_if_readable(path)
  if path ~= '' and vim.fn.filereadable(path) == 1 then
    vim.cmd.edit(vim.fn.fnameescape(vim.fn.fnamemodify(path, ':p')))
    return true
  end
  return false
end

-- gd that works in every buffer, trying in order:
--   1. "//path" (GN/Bazel source-root notation) resolved from the workspace root
--      (.gn marker, else git root); a bare "//dir" falls back to its BUILD.gn.
--   2. a path-looking <cfile> that resolves to a real file (&path + sibling dir).
--   3. LSP definition, if a server is attached.
--   4. Vim's built-in gd.
-- The path-looking guard (a slash or a .ext) stops it opening a stray file when
-- the cursor is on a plain symbol.
local function smart_goto_definition()
  local cfile = vim.fn.expand('<cfile>')

  local rooted = cfile:match('^//(.+)')
  if rooted then
    local root = vim.fs.root(0, { '.gn', '.git' }) or vim.fn.getcwd()
    if open_if_readable(root .. '/' .. rooted) then return end
    if vim.fn.isdirectory(root .. '/' .. rooted) == 1
       and open_if_readable(root .. '/' .. rooted .. '/BUILD.gn') then return end
  end

  if cfile ~= '' and (cfile:match('[/\\]') or cfile:match('%.%w+$')) then
    local target = vim.fn.findfile(cfile)
    if target == '' then
      local sibling = vim.fn.expand('%:p:h') .. '/' .. cfile
      if vim.fn.filereadable(sibling) == 1 then target = sibling end
    end
    if target ~= '' then
      vim.cmd.edit(vim.fn.fnameescape(vim.fn.fnamemodify(target, ':p')))
      return
    end
  end
  if #vim.lsp.get_clients({ bufnr = 0 }) > 0 then
    vim.lsp.buf.definition()
  else
    vim.cmd('normal! gd')
  end
end
M.smart_goto_definition = smart_goto_definition
_G.SmartGotoDefinition = smart_goto_definition

-- gr mirroring gd: LSP references when a capable server is attached, else a
-- project-wide grep for the word under the cursor (so gr still works in
-- languages with no LSP configured here). Both open the same fzf-lua list.
local function smart_references()
  local fzf = require('fzf-lua')
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
    if client.server_capabilities.referencesProvider then
      fzf.lsp_references()
      return
    end
  end
  fzf.grep_cword()
end
M.smart_references = smart_references
_G.SmartReferences = smart_references

-- Add each file's git root to its buffer-local &path so project-relative paths
-- (e.g. `base/foo.h`) resolve with gd/gf regardless of cwd. Non-recursive to
-- stay fast on a huge tree.
vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufNewFile' }, {
  callback = function(ev)
    local root = vim.fs.root(ev.buf, '.git')
    if root and not vim.tbl_contains(vim.opt_local.path:get(), root) then
      vim.opt_local.path:append(root)
    end
  end,
})

-- Inline diagnostics on by default; toggle with <leader>dv (config/keymaps.lua).
vim.diagnostic.config({ virtual_text = true })

vim.api.nvim_create_autocmd('LspAttach', {
  callback = function(ev)
    local map = function(lhs, rhs, desc)
      vim.keymap.set('n', lhs, rhs, { buffer = ev.buf, desc = desc })
    end
    local fzf = require('fzf-lua')
    map('<M-d>', smart_goto_definition,      'Goto definition / file under cursor')
    map('<M-r>', smart_references,           'Goto references')
    map('K',  vim.lsp.buf.hover,             'Hover docs')
    map('<leader>rn', vim.lsp.buf.rename,    'Rename symbol')
    map('<leader>ca', vim.lsp.buf.code_action,'Code action')

    map('<leader>ci', function()
      vim.lsp.buf.code_action({
        apply = true,
        filter = function(a)
          local t = (a.title or ''):lower()
          return t:find('import', 1, true) ~= nil or t:find('include', 1, true) ~= nil
        end,
      })
    end, 'Add import for symbol')

    map('<A-f>', function() vim.lsp.buf.format({ async = true }) end, 'Format document')
    vim.keymap.set('x', '<A-f>', function()
      local can_range = #vim.lsp.get_clients({ bufnr = 0, method = 'textDocument/rangeFormatting' }) > 0
      if can_range then
        vim.lsp.buf.format({ async = true })
      else
        vim.notify('Range formatting unsupported here', vim.log.levels.INFO)
      end
    end, { buffer = ev.buf, desc = 'Format selection' })

    -- Call clangd's custom request directly: the :ClangdSwitchSourceHeader user
    -- command isn't auto-registered on newer Neovim/lspconfig.
    map('gh', function()
      local client = vim.lsp.get_clients({ bufnr = 0, name = 'clangd' })[1]
      if not client then
        vim.notify('Switch header/source: clangd not attached to this buffer', vim.log.levels.WARN)
        return
      end
      local params = vim.lsp.util.make_text_document_params(0)
      client:request('textDocument/switchSourceHeader', params, function(err, result)
        if err then
          vim.notify('switchSourceHeader: ' .. tostring(err.message), vim.log.levels.ERROR)
        elseif not result or result == '' then
          vim.notify('No corresponding source/header file', vim.log.levels.INFO)
        else
          vim.cmd.edit(vim.uri_to_fname(result))
        end
      end, 0)
    end, 'Switch header/source')
    map('[d', vim.diagnostic.goto_prev,      'Prev diagnostic')
    map(']d', vim.diagnostic.goto_next,      'Next diagnostic')
    map('<leader>dd', vim.diagnostic.open_float, 'Show diagnostic under cursor')
    map('<leader>dl', fzf.diagnostics_document, 'List diagnostics (this file)')

    map('<leader>hu', function() vim.lsp.buf.typehierarchy('supertypes') end,
      'Inheritance tree: base types (up)')
    map('<leader>hd', function() vim.lsp.buf.typehierarchy('subtypes') end,
      'Inheritance tree: derived types (down)')
    map('<leader>hi', fzf.lsp_implementations, 'Implementors of virtual (overrides)')

    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if client and client.server_capabilities.inlayHintProvider then
      vim.lsp.inlay_hint.enable(true, { bufnr = ev.buf })
    end

    -- Highlight occurrences of the symbol under the cursor when it rests
    -- (updatetime), clear when it moves.
    if client and client.server_capabilities.documentHighlightProvider then
      local grp = vim.api.nvim_create_augroup('lsp_doc_highlight_' .. ev.buf, { clear = true })
      vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
        group = grp, buffer = ev.buf, callback = vim.lsp.buf.document_highlight,
      })
      vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
        group = grp, buffer = ev.buf, callback = vim.lsp.buf.clear_references,
      })
    end
  end,
})

return M
