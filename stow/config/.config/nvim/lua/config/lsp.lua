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

-- Web servers. ts_ls covers JS/TS/JSX/TSX, html/cssls/jsonls are the vscode-*
-- language servers, eslint adds project lint diagnostics + fix-all code actions,
-- and emmet expands abbreviations (div.foo>p) as completion items.

-- ts_ls advertises inlay hints but emits none until each kind is asked for.
local typescript_inlay_hints = {
  includeInlayParameterNameHints = 'literals',
  includeInlayParameterNameHintsWhenArgumentMatchesName = false,
  includeInlayFunctionParameterTypeHints = true,
  includeInlayVariableTypeHints = false,
  includeInlayPropertyDeclarationTypeHints = true,
  includeInlayFunctionLikeReturnTypeHints = true,
  includeInlayEnumMemberValueHints = true,
}

vim.lsp.config('ts_ls', {
  settings = {
    typescript = { inlayHints = typescript_inlay_hints },
    javascript = { inlayHints = typescript_inlay_hints },
  },
})

-- Plain CSS validation flags Tailwind/SCSS-style at-rules (@apply, @tailwind) as
-- unknown, so silence just that check; everything else stays on.
vim.lsp.config('cssls', {
  settings = {
    css = { lint = { unknownAtRules = 'ignore' } },
    scss = { lint = { unknownAtRules = 'ignore' } },
    less = { lint = { unknownAtRules = 'ignore' } },
  },
})

-- Emmet is completion-only, and its root-dir detection expects a web project;
-- attach it by filetype from any directory instead.
vim.lsp.config('emmet_language_server', {
  filetypes = { 'html', 'css', 'scss', 'less', 'javascriptreact', 'typescriptreact', 'vue', 'svelte' },
  root_dir = function(bufnr, on_dir)
    on_dir(vim.fs.root(bufnr, { '.git', 'package.json' }) or vim.fn.getcwd())
  end,
})

vim.lsp.enable({
  'clangd', 'pyright', 'rust_analyzer', 'omnisharp',
  'ts_ls', 'html', 'cssls', 'jsonls', 'eslint', 'emmet_language_server',
})

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
  vim.api.nvim_set_hl(0, '@lsp.type.unresolvedReference', { underdotted = true, sp = '#c678dd' })
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

-- Ask each attached server for the symbol's definition and pivot: if one of the
-- results is the location we're already sitting on (a variable resting on its own
-- definition), jump to that variable's *type* definition instead; otherwise open
-- the usual definitions picker. Line-based containment is enough — a definition's
-- name lives on a single line.
local function lsp_definition_or_typedef()
  local fzf = require('fzf-lua')
  local buf_uri = vim.uri_from_bufnr(0)
  local cur_line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(0),
    position = { line = cur_line, character = vim.api.nvim_win_get_cursor(0)[2] },
  }

  vim.lsp.buf_request_all(0, 'textDocument/definition', params, function(results)
    local on_def = false
    for _, res in pairs(results or {}) do
      local r = res.result
      local locs = (r == nil) and {} or ((r.uri or r.targetUri) and { r } or r)
      for _, loc in ipairs(locs) do
        local rng = loc.targetSelectionRange or loc.targetRange or loc.range
        if (loc.targetUri or loc.uri) == buf_uri and rng
           and cur_line >= rng.start.line and cur_line <= rng['end'].line then
          on_def = true
        end
      end
    end
    if on_def then
      fzf.lsp_typedefs({ jump1 = true })
    else
      fzf.lsp_definitions({ jump1 = true })
    end
  end)
end

-- gd that works in every buffer, trying in order:
--   1. "//path" (GN/Bazel source-root notation) resolved from the workspace root
--      (.gn marker, else git root); a bare "//dir" falls back to its BUILD.gn.
--   2. a path-looking <cfile> that resolves to a real file (&path + sibling dir).
--   3. LSP definition (fzf-lua picker) if a server is attached — or, when already
--      on the definition, the type's definition (see lsp_definition_or_typedef).
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
    -- fzf-lua picker (not vim.lsp.buf.definition): jump1 goes straight to a lone
    -- result, and the picker closes on selection instead of leaving the default
    -- handler's quickfix window open behind you.
    lsp_definition_or_typedef()
  else
    vim.cmd('normal! gd')
  end
end
M.smart_goto_definition = smart_goto_definition
_G.SmartGotoDefinition = smart_goto_definition

-- Lines holding the definition of the symbol under the cursor, keyed
-- "<file>:<lnum>". Used to drop the definition from the reference list:
-- `includeDeclaration = false` alone isn't enough, as some servers
-- (rust-analyzer for locals and parameters) report it as a plain reference.
local function definition_lines(client)
  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  local responses = vim.lsp.buf_request_sync(0, 'textDocument/definition', params, 500) or {}
  local lines = {}
  for _, response in pairs(responses) do
    local result = response.result or {}
    for _, location in ipairs(vim.islist(result) and result or { result }) do
      local uri = location.uri or location.targetUri
      local range = location.range or location.targetSelectionRange
      if uri and range then
        lines[vim.uri_to_fname(uri) .. ':' .. (range.start.line + 1)] = true
      end
    end
  end

  return lines
end

-- gr mirroring gd: LSP references when a capable server is attached, else a
-- project-wide grep for the word under the cursor (so gr still works in
-- languages with no LSP configured here). Both open the same fzf-lua list.
local function smart_references()
  local fzf = require('fzf-lua')
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
    if client.server_capabilities.referencesProvider then
      local definitions = definition_lines(client)
      fzf.lsp_references({
        jump1 = true,
        includeDeclaration = false,
        regex_filter = function(item)
          return not definitions[item.filename .. ':' .. item.lnum]
        end,
      })

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

local diagnostic_float_namespace = vim.api.nvim_create_namespace('diagnostic_float_severity')

local severity_labels = {
  [vim.diagnostic.severity.ERROR] = { 'Error', 'DiagnosticFloatingError' },
  [vim.diagnostic.severity.WARN]  = { 'Warn',  'DiagnosticFloatingWarn' },
  [vim.diagnostic.severity.INFO]  = { 'Info',  'DiagnosticFloatingInfo' },
  [vim.diagnostic.severity.HINT]  = { 'Hint',  'DiagnosticFloatingHint' },
}

-- One float line per line of each message, plus the highlight group each line
-- should get, so a wrapped multi-line message keeps its severity colour.
local function diagnostic_float_lines(diagnostics)
  local lines, highlights = {}, {}
  for _, diagnostic in ipairs(diagnostics) do
    local label, highlight = unpack(severity_labels[diagnostic.severity])
    local source = diagnostic.source and (' [' .. diagnostic.source .. ']') or ''
    for i, message_line in ipairs(vim.split(diagnostic.message, '\n', { trimempty = true })) do
      local first = i == 1
      local prefix = first and (label .. ': ') or string.rep(' ', #label + 2)
      table.insert(lines, prefix .. message_line .. (first and source or ''))
      table.insert(highlights, highlight)
    end
  end

  return lines, highlights
end

-- vim.diagnostic.open_float matches diagnostics by their start line, while the
-- underline is drawn across the whole lnum..end_lnum range -- so a multi-line
-- diagnostic (common in Rust) leaves squiggles on lines the float says nothing
-- about. Report every diagnostic whose range covers the cursor line instead.
local function open_covering_diagnostic_float()
  local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
  local covering = vim.tbl_filter(function(diagnostic)
    return diagnostic.lnum <= lnum and (diagnostic.end_lnum or diagnostic.lnum) >= lnum
  end, vim.diagnostic.get(0))

  if #covering == 0 then
    vim.notify('No diagnostic under cursor', vim.log.levels.INFO)
    return
  end

  table.sort(covering, function(a, b) return a.severity < b.severity end)
  local lines, highlights = diagnostic_float_lines(covering)
  local float_buf = vim.lsp.util.open_floating_preview(lines, '', {
    border = 'rounded',
    focus = false,
    focusable = true,
    wrap = true,
  })
  for i, highlight in ipairs(highlights) do
    vim.api.nvim_buf_set_extmark(float_buf, diagnostic_float_namespace, i - 1, 0, {
      end_col = #lines[i],
      hl_group = highlight,
    })
  end
end
M.open_covering_diagnostic_float = open_covering_diagnostic_float

vim.api.nvim_create_autocmd('LspAttach', {
  callback = function(ev)
    local map = function(lhs, rhs, desc)
      vim.keymap.set('n', lhs, rhs, { buffer = ev.buf, desc = desc })
    end
    local fzf = require('fzf-lua')
    map('<M-d>', smart_goto_definition,      'Goto definition / file under cursor')
    map('<M-r>', smart_references,           'Goto references')
    map('K',  vim.lsp.buf.hover,             'Hover docs')
    map('<leader>cr', vim.lsp.buf.rename,    'Rename symbol')
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

    map('<C-A-f>', function() vim.lsp.buf.format({ async = true }) end, 'Format document')
    vim.keymap.set('x', '<C-A-f>', function()
      local can_range = #vim.lsp.get_clients({ bufnr = 0, method = 'textDocument/rangeFormatting' }) > 0
      if can_range then
        vim.lsp.buf.format({ async = true })
      else
        vim.notify('Range formatting unsupported here', vim.log.levels.INFO)
      end
    end, { buffer = ev.buf, desc = 'Format selection' })

    -- Call clangd's custom request directly: the :ClangdSwitchSourceHeader user
    -- command isn't auto-registered on newer Neovim/lspconfig.
    map('<A-o>', function()
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
    map('<leader>dd', open_covering_diagnostic_float, 'Show diagnostic under cursor')
    map('<leader>dl', fzf.diagnostics_document, 'List diagnostics (this file)')

    map('<leader>hu', function() vim.lsp.buf.typehierarchy('supertypes') end,
      'Inheritance tree: base types (up)')
    map('<leader>hd', function() vim.lsp.buf.typehierarchy('subtypes') end,
      'Inheritance tree: derived types (down)')
    map('<leader>hi', function() fzf.lsp_implementations({ jump1 = true }) end,
      'Implementors of virtual (overrides)')

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
