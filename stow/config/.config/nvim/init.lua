-- dotfiles/stow/config/.config/nvim/init.lua
-- A beginner-friendly, VS-Code-flavored Neovim config (GENERAL / shared).
--
-- This is the general config, kept in the shared dotfiles repo and deployed by
-- GNU stow, which symlinks dotfiles/stow/config/.config/ into ~/.config/. At the
-- very end it optionally layers on machine-specific overrides via
-- $NVIM_LOCAL_INIT / $NVIM_LOCAL_TOPBAR (see section 9).
--
-- HOW THIS FILE IS ORGANIZED:
--   1. Leader key        (must come first)
--   2. Editor options
--   3. Plugin manager + plugins (lazy.nvim)
--   4. clangd / LSP setup
--   5. Keymaps
--   6. topbar shortcut bar
--   7. arrow key disable
--   8. explorer breadcrumb
--   9. machine-specific overrides hook
--
-- Press <leader>? for a searchable list of every mapping.

--------------------------------------------------------------------------------
-- 1. Leader key  (set BEFORE plugins load, or mappings bind to the wrong key)
--------------------------------------------------------------------------------
vim.g.mapleader = ' '       -- <Space> is your "command" key
vim.g.maplocalleader = ' '

-- Deployment: dotfiles/stow/config/.config/ is symlinked into ~/.config/ by GNU
-- stow (--no-folding), so at runtime this file is ~/.config/nvim/init.lua ->
-- repo. The topbar.json sibling is symlinked the same way and found via
-- stdpath('config'); lazy-lock.json is a real file stow leaves in ~/.config/nvim
-- (never written back into the repo). The topbar plugin is NOT symlinked into
-- ~/.config; it lives in this repo, found via $DOTFILES_DIR (exported by the
-- dotfiles setup.zsh). Optional machine-specific overrides are layered on at the
-- end via $NVIM_LOCAL_INIT / $NVIM_LOCAL_TOPBAR (see sect. 9).
local DOTFILES_DIR = vim.env.DOTFILES_DIR
if not DOTFILES_DIR or DOTFILES_DIR == '' then
  DOTFILES_DIR = vim.fn.expand('~/dotfiles')
end

--------------------------------------------------------------------------------
-- 2. Editor options
--------------------------------------------------------------------------------
local opt = vim.opt
opt.number = true            -- line numbers
opt.relativenumber = true    -- relative numbers (makes 5j / 3k jumps obvious)
opt.mouse = 'a'              -- mouse works, like VS Code
opt.clipboard = 'unnamedplus' -- y/p use the system clipboard
opt.smartindent = true
opt.ignorecase = true        -- case-insensitive search, always
opt.smartcase = false        -- ...even when the query contains a capital letter
opt.termguicolors = true     -- full color
opt.signcolumn = 'yes'       -- stable gutter (no text jump when errors appear)
opt.updatetime = 250
opt.timeoutlen = 350         -- mapping timeout (ms); also how long a pause on the
                             -- leader waits before the topbar menu opens
opt.scrolloff = 8            -- keep 8 lines visible above/below cursor
opt.undofile = true          -- persistent undo across sessions
opt.splitright = true
opt.splitbelow = true
opt.cursorline = true
-- NOTE: indentation width (expandtab/shiftwidth/tabstop) is intentionally left
-- at Neovim defaults here; project-specific styles are set in a local override.

-- Strip trailing whitespace on every write. winsaveview/winrestview keep the
-- cursor and scroll position put, and `keeppatterns` avoids stomping the last
-- search. Skips filetypes where trailing whitespace is meaningful — diff/patch
-- (stripping it would corrupt the file) and markdown (two trailing spaces are a
-- hard line break).
vim.api.nvim_create_autocmd('BufWritePre', {
  group = vim.api.nvim_create_augroup('trim_trailing_whitespace', { clear = true }),
  callback = function()
    if vim.tbl_contains({ 'diff', 'patch', 'markdown' }, vim.bo.filetype) then return end
    local view = vim.fn.winsaveview()
    vim.cmd([[keeppatterns %s/\s\+$//e]])
    vim.fn.winrestview(view)
  end,
})

--------------------------------------------------------------------------------
-- 3. Bootstrap lazy.nvim (the plugin manager) and declare plugins
--------------------------------------------------------------------------------
local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({ 'git', 'clone', '--filter=blob:none',
    'https://github.com/folke/lazy.nvim.git', '--branch=stable', lazypath })
end
vim.opt.rtp:prepend(lazypath)

require('lazy').setup({
  -- Colorscheme ---------------------------------------------------------------
  {
    'folke/tokyonight.nvim',
    priority = 1000,
    config = function() vim.cmd.colorscheme('tokyonight-night') end,
  },

  -- (The cheatsheet is the topbar plugin — see section 6 below.)

  -- Statusline at the bottom --------------------------------------------------
  {
    'nvim-lualine/lualine.nvim',
    opts = {
      -- globalstatus (one statusline for the whole editor, laststatus=3) so the
      -- reserved topbar window doesn't get a per-window statusline drawn as an
      -- extra row right beneath it. The topbar plugin also forces laststatus=3.
      options = { theme = 'tokyonight', globalstatus = true },
      -- Show the file's path relative to the cwd (path = 1) instead of just the
      -- bare filename (path = 0). Use 2 for absolute, 3 for absolute with ~.
      sections = { lualine_c = { { 'filename', path = 1 } } },
    },
  },

  -- LSP progress popups (e.g. clangd indexing status) in the corner -----------
  -- Purpose-built for showing $/progress as a small, lingering notification, so
  -- brief indexing bursts are actually visible (a statusline string flashed too
  -- fast). Auto-hooks LSP progress; no wiring needed.
  { 'j-hui/fidget.nvim', opts = {} },

  -- Multiple cursors (VS Code's Ctrl+Alt+Down) --------------------------------
  -- Neovim has no native multi-cursor; this adds real extra cursors. The core
  -- binding is "add a cursor on the line below/above at the same column".
  {
    'jake-stewart/multicursor.nvim',
    event = 'VeryLazy',
    config = function()
      local mc = require('multicursor-nvim')
      mc.setup()
      -- Add a cursor directly below / above on the same column (VS Code's
      -- Ctrl+Alt+Down / Up). <A-j>/<A-k> already move lines, so use Alt+Shift+j/k.
      -- (Ctrl+Alt+<key> isn't reliably delivered by terminals; plain Alt is.)
      vim.keymap.set({ 'n', 'x' }, '<A-J>', function() mc.lineAddCursor(1) end,
        { desc = 'Add cursor below (same column)' })
      vim.keymap.set({ 'n', 'x' }, '<A-K>', function() mc.lineAddCursor(-1) end,
        { desc = 'Add cursor above (same column)' })
      -- Bonus: add a cursor at the next / previous match of the word under the
      -- cursor (or the current visual selection) — grow a multi-selection.
      vim.keymap.set({ 'n', 'x' }, '<leader>mn', function() mc.matchAddCursor(1) end,
        { desc = 'Multicursor: add next match' })
      vim.keymap.set({ 'n', 'x' }, '<leader>mp', function() mc.matchAddCursor(-1) end,
        { desc = 'Multicursor: add prev match' })
      -- Mappings that live ONLY while extra cursors exist (a "layer"), so they
      -- don't shadow your normal keys. The callback is handed a `set` function
      -- (mode, lhs, rhs) — call it directly. <Esc> is how you LEAVE multicursor:
      -- first <Esc> re-enables frozen cursors, otherwise it clears them (back to
      -- a single cursor). <C-c> also clears, as an escape hatch.
      mc.addKeymapLayer(function(set)
        set({ 'n', 'x' }, '<Esc>', function()
          if not mc.cursorsEnabled() then mc.enableCursors()
          elseif mc.hasCursors() then mc.clearCursors() end
        end, { desc = 'Multicursor: enable / clear cursors' })
        set({ 'n', 'x' }, '<C-c>', mc.clearCursors, { desc = 'Multicursor: clear all cursors' })
      end)
    end,
  },

  -- File explorer sidebar (VS Code's file tree) -------------------------------
  {
    'nvim-tree/nvim-tree.lua',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    opts = {
      view = { width = 36 },
      -- Keep the tree highlighted on whatever buffer you're editing, and
      -- expand folders to reveal it — like VS Code's "reveal in explorer".
      update_focused_file = { enable = true },
    },
  },

  -- Fuzzy finder for everything (files, grep, buffers, LSP pickers) -----------
  -- fzf-lua streams results straight through the `fzf` binary, so it stays fast
  -- on very large monorepos (a Lua-table finder bogs down past a few hundred
  -- thousand files). It also previews via native vim.treesitter, so it needs no
  -- nvim-treesitter API and doesn't break against the treesitter `main` rewrite.
  {
    'ibhagwan/fzf-lua',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    config = function()
      require('fzf-lua').setup({
        files = {
          -- fd honours .gitignore (so build output is skipped); no --follow to
          -- avoid chasing symlinks around the tree.
          fd_opts = '--type f --color=never --hidden --exclude .git',
          -- Single-select only. With --multi (the default), marking 2+ entries and
          -- hitting <CR> runs file_edit_or_qf, which dumps them into the quickfix
          -- window — the "extra dialog with other paths". We just want to open the
          -- one file, so disable multi (splits/toggles actions are unaffected).
          fzf_opts = { ['--multi'] = false },
        },
        lsp = {
          -- Same story for LSP lists (gr references, gd, etc.): with --multi on,
          -- <CR> runs file_edit_or_qf, and a >1 selection is dumped into a
          -- quickfix window (botright copen) — the extra window at the bottom
          -- instead of jumping straight to the ref. Single-select fixes it.
          fzf_opts = { ['--multi'] = false },
        },
      })
    end,
  },

  -- Project-wide interactive find & replace (ripgrep-backed): live match list,
  -- edit the replacement, apply across all files from one buffer. <leader>fr.
  {
    'MagicDuck/grug-far.nvim',
    cmd = 'GrugFar',
    keys = {
      { '<leader>fr', '<cmd>GrugFar<cr>', desc = 'Find & replace (project)' },
      -- Visual: open prefilled with the selected text (searches the whole project).
      { '<leader>fr', ":<C-u>lua require('grug-far').with_visual_selection()<CR>",
        mode = 'x', desc = 'Find & replace (selection)' },
    },
    opts = {},
  },

  -- Treesitter: better syntax highlighting ------------------------------------
  -- Uses the 'main' branch: the 'master' branch caps out below Neovim 0.12 and
  -- crashes its query engine (the "attempt to call method 'range'" error). On
  -- 'main', parser install is explicit and highlighting is Neovim-native via
  -- vim.treesitter.start(). Requires the tree-sitter CLI + a C compiler.
  {
    'nvim-treesitter/nvim-treesitter',
    branch = 'main',
    lazy = false,        -- the main branch does not support lazy-loading
    build = ':TSUpdate',
    config = function()
      -- Install parsers (async; a no-op once present). markdown needs BOTH
      -- 'markdown' (block structure) and 'markdown_inline' (inline spans).
      -- Project-specific parsers (e.g. 'gn') can be added by a local override.
      require('nvim-treesitter').install({
        'c', 'cpp', 'lua', 'python', 'rust', 'bash', 'json',
        'markdown', 'markdown_inline',
      })

      -- 'main' does not auto-enable highlighting; turn it on per-filetype.
      -- Skip huge generated files (some large repos contain them).
      vim.api.nvim_create_autocmd('FileType', {
        pattern = { 'c', 'cpp', 'lua', 'python', 'rust', 'sh', 'bash', 'json',
                    'markdown' },
        callback = function(ev)
          local name = vim.api.nvim_buf_get_name(ev.buf)
          local ok, stats = pcall((vim.uv or vim.loop).fs_stat, name)
          if ok and stats and stats.size > 256 * 1024 then return end
          pcall(vim.treesitter.start)
        end,
      })
    end,
  },

  -- LSP client config helper --------------------------------------------------
  { 'neovim/nvim-lspconfig' },

  -- LSP server installer (mason) ----------------------------------------------
  -- Fetches language-server binaries into a private dir and puts them on
  -- Neovim's PATH, so you don't install pyright / rust-analyzer system-wide.
  -- mason-lspconfig auto-installs the servers in ensure_installed on first
  -- launch (a one-time download; pyright needs Node, rust-analyzer is a
  -- prebuilt binary). clangd is intentionally NOT mason-managed: on the
  -- Chromium tree we use the version-matched tree clangd (see local override).
  { 'williamboman/mason.nvim', opts = {} },
  {
    'williamboman/mason-lspconfig.nvim',
    dependencies = { 'williamboman/mason.nvim', 'neovim/nvim-lspconfig' },
    opts = { ensure_installed = { 'pyright', 'rust_analyzer' } },
  },

  -- Autocompletion ------------------------------------------------------------
  {
    'hrsh7th/nvim-cmp',
    dependencies = {
      'hrsh7th/cmp-nvim-lsp',
      'L3MON4D3/LuaSnip',
      'saadparwaiz1/cmp_luasnip',
    },
    config = function()
      local cmp = require('cmp')
      cmp.setup({
        snippet = { expand = function(a) require('luasnip').lsp_expand(a.body) end },
        mapping = cmp.mapping.preset.insert({
          ['<C-Space>'] = cmp.mapping.complete(),     -- force-open suggestions
          ['<CR>']      = cmp.mapping.confirm({ select = true }), -- accept
          ['<Tab>']     = cmp.mapping.select_next_item(),
          ['<S-Tab>']   = cmp.mapping.select_prev_item(),
          ['<C-f>']     = cmp.mapping.scroll_docs(4),  -- scroll doc popup down
          ['<C-b>']     = cmp.mapping.scroll_docs(-4), -- scroll doc popup up
        }),
        sources = { { name = 'nvim_lsp' }, { name = 'luasnip' } },
      })
    end,
  },

  -- GitHub Copilot: inline AI autocomplete (VS Code-style ghost text) ---------
  -- Suggestions appear greyed-out ahead of the cursor as you type; accept with
  -- <C-l>. NOT <Tab> — that's nvim-cmp's select-next above, so Copilot lives on
  -- its own key and the two completion systems don't fight.
  {
    'zbirenbaum/copilot.lua',
    cmd = 'Copilot',
    event = 'InsertEnter',
    opts = {
      suggestion = {
        auto_trigger = true,      -- stream ghost text without pressing a key
        keymap = {
          accept = '<C-l>',       -- accept the whole suggestion
          next = '<M-]>',         -- cycle to the next suggestion
          prev = '<M-[>',
          dismiss = '<C-]>',
        },
      },
      panel = { enabled = false }, -- ghost text only; no split-panel UI
    },
  },

  -- Git: inline blame + hunks (gitsigns) and full git interface (fugitive) ----
  {
    'lewis6991/gitsigns.nvim',
    opts = {
      -- GitLens-style ghost text at end of the current line. On by default;
      -- toggle with <leader>gB. (Popup blame via <leader>gb works regardless.)
      current_line_blame = true,
      current_line_blame_opts = { delay = 250, virt_text_pos = 'eol' },
    },
  },
  { 'tpope/vim-fugitive' },

  -- Merge-conflict highlighting + resolution (git-conflict) -------------------
  -- Colors the two sides of a conflict (<<<< current / ==== / >>>> incoming)
  -- with distinct backgrounds so the regions — not just the marker lines —
  -- stand out, and adds :GitConflict* commands to jump between conflicts and
  -- pick a side. default_mappings is OFF: its defaults grab `co`/`ct`, and `ct`
  -- is the vim change-till operator; we bind our own keys in section 5 instead.
  {
    'akinsho/git-conflict.nvim',
    version = '*',        -- track tagged releases, not bleeding main
    opts = { default_mappings = false },
  },

  -- Auto-close pairs: typing ( [ { ` ' " inserts the pair and puts the cursor
  -- between them. Also skips over a closing char you type yourself, deletes both
  -- halves on backspace, and is smart about quotes (won't pair a ' mid-word like
  -- in don't). map_cr = false so it leaves <CR> to nvim-cmp (accept completion).
  {
    'windwp/nvim-autopairs',
    event = 'InsertEnter',
    config = function()
      require('nvim-autopairs').setup({ map_cr = false })
      -- Insert () (cursor inside) after confirming a function/method from cmp.
      -- Done here (on InsertEnter) so both cmp (loaded at startup) and autopairs
      -- are available. Registered once.
      local ok, cmp = pcall(require, 'cmp')
      if ok then
        cmp.event:on('confirm_done',
          require('nvim-autopairs.completion.cmp').on_confirm_done())
      end
    end,
  },
}, {
  -- show a clean install/update UI
  ui = { border = 'rounded' },
  -- Lockfile stays at the default stdpath('config')/lazy-lock.json, which is
  -- exactly where the .config copy places it.
})

--------------------------------------------------------------------------------
-- 4. clangd / LSP setup
--------------------------------------------------------------------------------
-- General C++ setup uses the system `clangd`. A local override may replace the
-- `cmd` (binary path + project-tuned flags) when running in that environment.
local capabilities = require('cmp_nvim_lsp').default_capabilities()

-- Native LSP API (Neovim 0.11+). Apply completion capabilities to EVERY server
-- via the '*' wildcard config, so nvim-cmp works in any language (clangd,
-- pyright, rust_analyzer, …) — not just C/C++.
vim.lsp.config('*', { capabilities = capabilities })

-- clangd: nvim-lspconfig ships the default definition (filetypes, root markers);
-- we merge the system-binary `cmd` on top (a local override swaps in Chromium's).
vim.lsp.config('clangd', { cmd = { 'clangd' } })

-- Enable the servers we use. pyright (Python) and rust_analyzer (Rust) are
-- installed by mason (see plugins above); nvim-lspconfig supplies each server's
-- default cmd/filetypes/root markers. Enabling registers a FileType hook that
-- launches the right server when you open a matching buffer — this is what makes
-- gd/gr/K/rename/diagnostics LSP-powered in those languages, not just C/C++.
vim.lsp.enable({ 'clangd', 'pyright', 'rust_analyzer' })

-- Make the "symbol under cursor" highlight visible and theme-aware. Re-apply
-- on ColorScheme so it survives a theme switch.
local function set_reference_hl()
  for _, g in ipairs({ 'LspReferenceText', 'LspReferenceRead', 'LspReferenceWrite' }) do
    vim.api.nvim_set_hl(0, g, { link = 'Visual' })
  end
end
set_reference_hl()
vim.api.nvim_create_autocmd('ColorScheme', { callback = set_reference_hl })

-- Smart "go to definition" that works in EVERY buffer, not just clangd ones:
--   1. A "//path" (GN/Bazel source-root notation, e.g. //base/foo.gni in .gn
--      files) resolves relative to the workspace root (.gn marker, else git
--      root); a bare "//dir" falls back to that dir's BUILD.gn.
--   2. Otherwise, if the text under the cursor looks like a path and resolves to
--      a real file (searching &path + the current file's directory), open it.
--   3. Otherwise, if a language server is attached, use its definition.
--   4. Otherwise, fall back to Vim's built-in gd (local declaration).
-- The "looks like a path" guard (has a slash or a .ext) stops it from opening a
-- stray file when the cursor is on a plain symbol name.
local function open_if_readable(path)
  if path ~= '' and vim.fn.filereadable(path) == 1 then
    vim.cmd.edit(vim.fn.fnameescape(vim.fn.fnamemodify(path, ':p')))
    return true
  end
  return false
end

local function smart_goto_definition()
  local cfile = vim.fn.expand('<cfile>')

  -- "//path" — source-root-relative (GN/Bazel). Strip "//", resolve from root.
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
-- Expose it so a local override (and anything else) can reuse the same behavior.
_G.SmartGotoDefinition = smart_goto_definition

-- Smart "go to references" that works in EVERY buffer, mirroring gd above:
--   1. If a language server with references support is attached, ask it (exact,
--      scope-aware — clangd for C/C++).
--   2. Otherwise fall back to a project-wide grep for the word under the cursor,
--      so `gr` still finds usages in languages with no LSP configured here (e.g.
--      python3, where only clangd is set up). Both open the same fzf-lua list.
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
_G.SmartReferences = smart_references

-- Add each file's git root to its buffer-local &path, so project-relative
-- paths (e.g. include-style `base/foo.h`) resolve with gd/gf no matter what the
-- cwd is. Non-recursive, so it stays fast even on a huge tree.
vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufNewFile' }, {
  callback = function(ev)
    local root = vim.fs.root(ev.buf, '.git')
    if root and not vim.tbl_contains(vim.opt_local.path:get(), root) then
      vim.opt_local.path:append(root)
    end
  end,
})

-- Buffer-local keymaps that only exist once a language server attaches.
vim.api.nvim_create_autocmd('LspAttach', {
  callback = function(ev)
    local map = function(lhs, rhs, desc)
      vim.keymap.set('n', lhs, rhs, { buffer = ev.buf, desc = desc })
    end
    local fzf = require('fzf-lua')
    map('gd', smart_goto_definition,         'Goto definition / file under cursor')
    map('gD', vim.lsp.buf.declaration,       'Goto declaration')
    map('gr', smart_references,              'Goto references')
    map('gi', vim.lsp.buf.implementation,    'Goto implementation')
    map('K',  vim.lsp.buf.hover,             'Hover docs')
    map('<leader>rn', vim.lsp.buf.rename,    'Rename symbol')
    map('<leader>ca', vim.lsp.buf.code_action,'Code action')
    -- Switch between a C/C++ source and its header. We call clangd's custom LSP
    -- request directly rather than the :ClangdSwitchSourceHeader user command,
    -- which isn't auto-registered on newer Neovim/lspconfig.
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

    -- Highlight every occurrence of the symbol under the cursor (LSP document
    -- highlight, VS Code style). Highlights when the cursor rests (updatetime
    -- is 250ms above) and clears the moment it moves.
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
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

--------------------------------------------------------------------------------
-- 5. Global keymaps
--------------------------------------------------------------------------------
local map = vim.keymap.set
local fzf = require('fzf-lua')

-- Open the tree focused on the current file (reveals + jumps to it), VS Code style.
map('n', '<leader>e',  '<cmd>NvimTreeFindFileToggle<cr>', { desc = 'Explorer (reveal current file)' })
-- Goto file-under-cursor / definition — works in every buffer (see section 4).
map('n', 'gd', smart_goto_definition, { desc = 'Goto definition / file under cursor' })
-- Goto references — LSP when attached, else grep word under cursor (see sect. 4).
map('n', 'gr', smart_references, { desc = 'Goto references' })
-- All pickers use fzf-lua — files/grep/buffers plus LSP (gr references,
-- implementors) and help/keymaps.
-- Find-files with recently-visited files floated to the top: prepend this cwd's
-- entries from :oldfiles (most-recent first, existing only) to the streamed `fd`
-- list, dedupe (recents win), and tell fzf to break score ties by input order
-- (--tiebreak=index) so a recent match outranks an equally-good non-recent one.
-- Stays fast on huge trees because fd still streams — we only prepend a handful
-- of lines. fd command mirrors the fd_opts in the fzf-lua setup above.
local function find_files_recent_first()
  local cwd = vim.uv.cwd()
  local prefix = cwd .. '/'
  local seen, recent = {}, {}
  for _, f in ipairs(vim.v.oldfiles) do
    if f:sub(1, #prefix) == prefix and vim.uv.fs_stat(f) then
      local rel = f:sub(#prefix + 1)
      if rel ~= '' and not seen[rel] then
        seen[rel] = true
        recent[#recent + 1] = vim.fn.shellescape(rel)
      end
    end
  end
  local fd = vim.fn.executable('fd') == 1 and 'fd' or 'fdfind'
  local find = fd .. ' --type f --color=never --hidden --exclude .git'
  local prepend = #recent > 0 and ("printf '%s\\n' " .. table.concat(recent, ' ') .. '; ') or ''
  -- awk keeps the first occurrence of each path, so a recent line suppresses its
  -- later duplicate from fd; non-recent order is left as fd emits it.
  local cmd = '{ ' .. prepend .. find .. "; } | awk '!seen[$0]++'"
  fzf.files({ cmd = cmd, fzf_opts = { ['--tiebreak'] = 'index', ['--multi'] = false } })
end
map('n', '<C-p>',      find_files_recent_first,  { desc = 'Find files (recent first)' })
map('n', '<leader>ff', find_files_recent_first,  { desc = 'Find files (recent first)' })
-- Grep in cwd. Append ` -- <glob>` to filter files, VS Code "files to include"
-- style, e.g.  TODO -- *.cc   or   parse -- *.{h,cc} !*test*
-- (live_grep has glob parsing built in; live_grep_glob is deprecated.)
map('n', '<leader>fg', fzf.live_grep,            { desc = 'Grep in project (+ file glob)' })
map('n', '<leader>fb', fzf.buffers,              { desc = 'Open buffers' })
map('n', '<leader>fh', fzf.helptags,             { desc = 'Help tags' })
-- Jump list back/forward (aliases for native <C-o>/<C-i>, so they can live
-- under the topbar's "goto" (g) submenu). VS Code's Alt-Left / Alt-Right.
map('n', 'g[', '<C-o>', { desc = 'Jump back' })
map('n', 'g]', '<C-i>', { desc = 'Jump forward' })
-- Move focus between windows/splits without the <C-w> prefix (e.g. hop between
-- the nvim-tree sidebar and your code). <C-w>hjkl still works too.
map('n', '<C-h>', '<C-w>h', { desc = 'Focus window left' })
map('n', '<C-j>', '<C-w>j', { desc = 'Focus window below' })
map('n', '<C-k>', '<C-w>k', { desc = 'Focus window above' })
map('n', '<C-l>', '<C-w>l', { desc = 'Focus window right' })
-- Move the current line (normal) or selection (visual) down/up, VS Code
-- Alt-Down / Alt-Up. Reindents after the move.
map('n', '<A-j>', '<cmd>m .+1<cr>==', { desc = 'Move line down' })
map('n', '<A-k>', '<cmd>m .-2<cr>==', { desc = 'Move line up' })
map('x', '<A-j>', ":m '>+1<cr>gv=gv", { desc = 'Move selection down', silent = true })
map('x', '<A-k>', ":m '<-2<cr>gv=gv", { desc = 'Move selection up', silent = true })
-- Copy the current file's path to the system clipboard: yp = relative to cwd,
-- yP = full (absolute) path.
map('n', '<leader>yp', function()
  local rel = vim.fn.expand('%:.')
  vim.fn.setreg('+', rel)
  vim.notify('Copied path: ' .. rel)
end, { desc = 'Copy relative path' })
map('n', '<leader>yP', function()
  local abs = vim.fn.expand('%:p')
  vim.fn.setreg('+', abs)
  vim.notify('Copied path: ' .. abs)
end, { desc = 'Copy full (absolute) path' })
map('n', '<leader>w',  '<cmd>write<cr>',         { desc = 'Save file' })
map('n', '<leader>q',  '<cmd>quit<cr>',          { desc = 'Quit window' })
map('n', '<Esc>',      '<cmd>nohlsearch<cr>',    { desc = 'Clear search highlight' })

-- Line-jump shortcuts (home row): H = start of line, L = end of line (like `$`).
-- H is "smart" and toggles between the first non-blank char (like `^`) and the
-- very start of the line (like `0`):
--   * from anywhere past the indent → first non-blank char
--   * when only whitespace is to the left (at/inside the indent) → col 0
--   * when already at col 0 → back to the first non-blank char
--   * all-blank line → col 0
-- expr = true so a single mapping returns the right motion for normal, visual
-- and operator-pending modes (e.g. dL to end, yH to start), replacing H/L's
-- default "top/bottom of screen" jumps.
local function smart_home()
  local col = vim.fn.col('.')
  -- 1-indexed column of first non-blank; 0 when the line is entirely blank.
  local first = vim.fn.match(vim.fn.getline('.'), '\\S') + 1
  if first == 0 then
    return '0'   -- all-blank line → very start
  end
  if col == 1 then
    return '^'   -- already at the very start → jump to first non-blank
  end
  if col <= first then
    return '0'   -- only whitespace to the left → very start
  end
  return '^'     -- otherwise → first non-blank char
end
map({ 'n', 'x', 'o' }, 'H', smart_home, { expr = true, desc = 'Start of line (smart: non-blank, else col 0)' })
map({ 'n', 'x', 'o' }, 'L', '$', { desc = 'End of line (like $)' })

-- Show ALL keybindings (searchable full list via fzf-lua):
map('n', '<leader>?', fzf.keymaps, { desc = 'Show all keybindings' })

-- Git blame / history (gitsigns + fugitive) ----------------------------------
-- <leader>gb : popup with full blame + diff for the line under the cursor
-- <leader>gB : toggle GitLens-style inline blame ghost text (follows cursor)
-- <leader>gv : full side-by-side blame column for the whole file
-- <leader>gl : history of the current line (or visually-selected lines)
-- <leader>gc : last change on the line, wherever it lives — working-tree diff
--              if uncommitted, else the commit that last touched it (msg + diff)
-- <leader>gr : restore the line — discard working-tree changes on it (or on the
--              visually-selected lines), reverting to the committed version
-- ]x / [x    : jump to the next / previous merge conflict (git-conflict)
-- <leader>gx : resolve the conflict under the cursor — o=ours, t=theirs,
--              b=both, n=none. Conflict highlighting itself is automatic.
map('n', '<leader>gb', function() require('gitsigns').blame_line({ full = true }) end,
  { desc = 'Blame line (popup)' })
map('n', '<leader>gB', function() require('gitsigns').toggle_current_line_blame() end,
  { desc = 'Toggle inline blame' })
map('n', '<leader>gv', '<cmd>Git blame<cr>', { desc = 'Blame column (side-by-side)' })
-- Line history: build a `git log -L <start>,<end>:<file>` for the line/range.
map('n', '<leader>gl', function()
  local l = vim.fn.line('.')
  vim.cmd(string.format('Git log -L %d,%d:%%', l, l))
end, { desc = 'Line history' })
map('x', '<leader>gl', function()
  local s = vim.fn.line('v')
  local e = vim.fn.line('.')
  if s > e then s, e = e, s end
  vim.cmd(string.format('Git log -L %d,%d:%%', s, e))
end, { desc = 'Line history (selection)' })
-- Last change on the line: preview the working-tree diff if the line sits in an
-- uncommitted hunk, otherwise blame the commit that last touched it. <leader>gb
-- only ever does the latter and shows a bare "Not Committed Yet" for edits.
map('n', '<leader>gc', function()
  local gs = require('gitsigns')
  local lnum = vim.fn.line('.')
  for _, h in ipairs(gs.get_hunks() or {}) do
    local first = h.added.start
    -- A pure deletion (added.count == 0) is anchored on its start line.
    local last = first + math.max(h.added.count, 1) - 1
    if lnum >= first and lnum <= last then
      gs.preview_hunk()            -- uncommitted: working-tree diff
      return
    end
  end
  gs.blame_line({ full = true })   -- committed: last commit + its diff
end, { desc = 'Last change on line (working tree or last commit)' })
-- Restore the current line to its committed state (discard working-tree edits).
-- reset_hunk with a {first,last} range scopes the reset to just those lines
-- instead of the whole hunk.
map('n', '<leader>gr', function()
  local l = vim.fn.line('.')
  require('gitsigns').reset_hunk({ l, l })
end, { desc = 'Restore line (discard changes)' })
map('x', '<leader>gr', function()
  local s = vim.fn.line('v')
  local e = vim.fn.line('.')
  if s > e then s, e = e, s end
  require('gitsigns').reset_hunk({ s, e })
end, { desc = 'Restore lines (discard changes)' })
-- Merge conflicts (git-conflict.nvim). Highlighting is automatic in any buffer
-- containing conflict markers; these commands only act when a conflict exists.
map('n', ']x', '<cmd>GitConflictNextConflict<cr>', { desc = 'Next git conflict' })
map('n', '[x', '<cmd>GitConflictPrevConflict<cr>', { desc = 'Prev git conflict' })
map('n', '<leader>gxo', '<cmd>GitConflictChooseOurs<cr>',   { desc = 'Conflict: choose ours (current)' })
map('n', '<leader>gxt', '<cmd>GitConflictChooseTheirs<cr>', { desc = 'Conflict: choose theirs (incoming)' })
map('n', '<leader>gxb', '<cmd>GitConflictChooseBoth<cr>',   { desc = 'Conflict: choose both' })
map('n', '<leader>gxn', '<cmd>GitConflictChooseNone<cr>',   { desc = 'Conflict: choose none' })

--------------------------------------------------------------------------------
-- 6. topbar: always-on shortcut bar (github.com/SamuelSill/topbar)
--------------------------------------------------------------------------------
-- Shows your shortcuts in a reserved, multi-line bar pinned to the top of the
-- editor (content is pushed down, not hidden) and drills down as you type. Edit
-- the layout in topbar.json and run :TopbarReload — no restart needed. NOTE:
-- topbar forces laststatus=3 (one global statusline) because a reserved top
-- window under laststatus=2 would draw its own statusline as an extra row; the
-- lualine spec above is set to globalstatus=true to match. The general
-- layout lives here; an optional machine-specific layout ($NVIM_LOCAL_TOPBAR)
-- is merged on top. The plugin is a git submodule at DOTFILES_DIR/topbar (run
-- `git submodule update --init` after cloning); we load it off runtimepath
-- rather than symlinking it into ~/.config.
local topbar_dir = DOTFILES_DIR .. '/topbar'
if vim.fn.isdirectory(topbar_dir) == 1 then
  vim.opt.runtimepath:append(topbar_dir)
  -- General layout: the stow-symlinked file next to this init; fall back to the
  -- repo copy for a non-stowed / standalone checkout.
  local general_json = vim.fn.stdpath('config') .. '/topbar.json'
  if not (vim.uv or vim.loop).fs_stat(general_json) then
    general_json = DOTFILES_DIR .. '/stow/config/.config/nvim/topbar.json'
  end
  local topbar_configs = { general_json }
  -- Optional machine-specific layout (not symlinked into ~/.config): merge it.
  local local_topbar = vim.env.NVIM_LOCAL_TOPBAR
  if local_topbar and local_topbar ~= '' and (vim.uv or vim.loop).fs_stat(local_topbar) then
    table.insert(topbar_configs, local_topbar)
  end
  require('topbar').setup({ configs = topbar_configs })
end

--------------------------------------------------------------------------------
-- 7. arrow buttons: disable
--------------------------------------------------------------------------------
vim.keymap.set({ "n", "i", "v" }, "<Up>", "<Nop>", { silent = true })
vim.keymap.set({ "n", "i", "v" }, "<Down>", "<Nop>", { silent = true })
vim.keymap.set({ "n", "i", "v" }, "<Left>", "<Nop>", { silent = true })
vim.keymap.set({ "n", "i", "v" }, "<Right>", "<Nop>", { silent = true })

--------------------------------------------------------------------------------
-- 8. Explorer breadcrumb: pin the current folder hierarchy at the top of the
--    tree. nvim-tree has no true multi-line sticky scroll (upstream issue
--    #2650 is still open), so we render the ancestor-folder chain of the node
--    under the cursor into the tree window's winbar -- it stays visible at the
--    top no matter how many files you scroll past in a deep folder.
--------------------------------------------------------------------------------
local function nvimtree_breadcrumb()
  local ok, api = pcall(require, 'nvim-tree.api')
  if not ok then return end
  local node = api.tree.get_node_under_cursor()
  local parts = {}
  if node and node.absolute_path then
    -- Path relative to the cwd, split into its folder components.
    local rel = vim.fn.fnamemodify(node.absolute_path, ':~:.')
    parts = vim.split(rel, '/', { trimempty = true })
    if node.type ~= 'directory' then table.remove(parts) end  -- drop the filename
  end
  if #parts == 0 then parts = { vim.fn.fnamemodify(vim.fn.getcwd(), ':t') } end
  vim.wo.winbar = ' %#NvimTreeFolderName#' .. table.concat(parts, '  ')
end

vim.api.nvim_create_autocmd({ 'CursorMoved', 'BufWinEnter' }, {
  callback = function()
    if vim.bo.filetype == 'NvimTree' then nvimtree_breadcrumb() end
  end,
})

--------------------------------------------------------------------------------
-- 9. Machine-specific overrides (optional). If the environment points
--    $NVIM_LOCAL_INIT at a Lua file, load it last so it can override anything
--    above. Set by whatever per-machine setup sources this repo; absent on a
--    plain checkout, in which case this is a no-op.
--------------------------------------------------------------------------------
local local_init = vim.env.NVIM_LOCAL_INIT
if local_init and local_init ~= '' and (vim.uv or vim.loop).fs_stat(local_init) then
  dofile(local_init)
end
