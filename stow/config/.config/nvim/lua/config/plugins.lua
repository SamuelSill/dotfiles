-- config/plugins.lua -- lazy.nvim bootstrap + every plugin declaration.
-- The leader key is set in init.lua before this loads, so mappings bind right.

local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({ 'git', 'clone', '--filter=blob:none',
    'https://github.com/folke/lazy.nvim.git', '--branch=stable', lazypath })
end
vim.opt.rtp:prepend(lazypath)

require('lazy').setup({
  {
    'folke/tokyonight.nvim',
    priority = 1000,
    config = function()
      require('tokyonight').setup({
        style = 'night',
        -- on_colors runs after tokyonight derives every bg_* from bg/bg_dark, so
        -- each background must be set explicitly or it keeps the stock value.
        on_colors = function(c)
          c.bg           = '#0d0e14'
          c.bg_dark      = '#08090d'
          c.bg_dark1     = '#050508'
          c.bg_popup     = '#08090d'
          c.bg_statusline = '#08090d'
          c.bg_sidebar   = '#08090d'
          c.bg_float     = '#08090d'
          c.bg_visual    = '#2a3158'
          c.bg_search    = '#2a3158'
          c.black        = '#000000'
          c.border       = '#3b4261'
          -- Brighter fg + comments to lift contrast against the darker canvas.
          c.fg           = '#d4dbf7'
          c.fg_dark      = '#b4bce0'
          c.comment      = '#7a83ad'
        end,
      })
      vim.cmd.colorscheme('tokyonight-night')
    end,
  },

  {
    'nvim-lualine/lualine.nvim',
    -- globalstatus matches the topbar's forced laststatus=3, so no per-window
    -- statusline is drawn as an extra row under the reserved topbar window.
    opts = {
      options = { theme = 'tokyonight', globalstatus = true },
      sections = {
        lualine_b = { 'diagnostics' },
        lualine_c = { { 'filename', path = 1 } },  -- path relative to cwd
        lualine_x = { 'fileformat' },
        lualine_y = {},
      },
    },
  },

  -- Shows LSP $/progress (e.g. clangd indexing) as a lingering corner popup, so
  -- brief bursts are actually visible where a statusline string flashes too fast.
  { 'j-hui/fidget.nvim', opts = {} },

  {
    'nvim-tree/nvim-tree.lua',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    opts = {
      view = { width = 36 },
      update_focused_file = { enable = true },
    },
  },

  -- fzf-lua streams results through the `fzf` binary, so it stays fast on huge
  -- monorepos where a Lua-table finder bogs down; previews via native
  -- vim.treesitter, so it's unaffected by the treesitter `main` rewrite.
  {
    'ibhagwan/fzf-lua',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    config = function()
      vim.g.fzf_history_dir = vim.fn.stdpath('state') .. '/fzf-lua-history'
      vim.fn.mkdir(vim.g.fzf_history_dir, 'p')

      -- Preview <-> prompt focus, vim-style: from the prompt, whichever of
      -- ctrl-h/j/k/l points at the preview enters it, and from the preview any of
      -- them returns. A key that doesn't point at the preview is forwarded to fzf
      -- as its raw control byte, so ctrl-h stays backspace and ctrl-j/ctrl-k stay
      -- list navigation.
      local focus_directions = { h = 'left', j = 'down', k = 'up', l = 'right' }
      local fzf_control_bytes = { h = '\8', j = '\10', k = '\11', l = '\12' }

      -- The file swapped into the preview window, kept so it can be surfaced
      -- again if the picker closes while it still holds unsaved edits.
      local edited = nil

      local function focus_prompt()
        local win = require('fzf-lua.win').__SELF()
        if not win or not win.fzf_winid then return end

        vim.api.nvim_set_current_win(win.fzf_winid)
        vim.cmd('startinsert')
      end

      local function previewed_file_buffer()
        local win = require('fzf-lua.win').__SELF()
        local previewer = win and win._previewer
        local entry = previewer and previewer.loaded_entry
        if not entry then return nil end

        if entry.bufnr and vim.api.nvim_buf_is_valid(entry.bufnr) then return entry.bufnr end
        if not entry.path then return nil end

        local fzf_path = require('fzf-lua.path')
        local file = fzf_path.is_absolute(entry.path) and entry.path
          or fzf_path.join({ previewer.opts.cwd or vim.uv.cwd(), entry.path })

        return vim.fn.bufadd(file)
      end

      -- fzf-lua previews a throwaway copy of the file, so edits made in it would
      -- go nowhere. Swap in the file's real buffer on focus: the preview window
      -- becomes an ordinary window on the file (edit it, `:w` it) with the picker
      -- still running behind it. The copy is kept loaded rather than wiped, so
      -- fzf-lua's preview cache doesn't end up pointing at a dead buffer.
      -- A leftover swapfile would pop the recovery prompt (or fail outright) from
      -- inside the preview, so answer it here: take the file when the owning
      -- process is gone, otherwise settle for a read-only view of it.
      local function load_answering_swap_prompt(buf)
        local group = vim.api.nvim_create_augroup('FzfLuaPreviewSwap', { clear = true })
        vim.api.nvim_create_autocmd('SwapExists', {
          group = group,
          callback = function()
            local pid = vim.fn.swapinfo(vim.v.swapname).pid
            local owner_alive = type(pid) == 'number' and pid > 0
              and select(1, pcall(vim.uv.kill, pid, 0)) == true
            vim.v.swapchoice = owner_alive and 'o' or 'e'
          end,
        })

        local loaded = pcall(vim.fn.bufload, buf)
        vim.api.nvim_del_augroup_by_id(group)

        return loaded
      end

      local function show_real_file_in_preview(preview_winid)
        local buf = previewed_file_buffer()
        if not buf or not load_answering_swap_prompt(buf) then return end

        local position = vim.api.nvim_win_get_cursor(preview_winid)
        -- fzf-lua styles the preview through buffer-local window options, which
        -- the incoming buffer wouldn't inherit.
        local style = {}
        for _, option in ipairs({ 'number', 'relativenumber', 'cursorline', 'wrap', 'signcolumn' }) do
          style[option] = vim.wo[preview_winid][0][option]
        end

        vim.bo[vim.api.nvim_win_get_buf(preview_winid)].bufhidden = 'hide'
        vim.api.nvim_win_set_buf(preview_winid, buf)
        pcall(vim.api.nvim_win_set_cursor, preview_winid, position)
        for option, value in pairs(style) do
          vim.wo[preview_winid][0][option] = value
        end
        edited = { buf = buf, position = position }
      end

      -- Closing the picker takes the preview window with it, which would otherwise
      -- leave unsaved edits in a buffer the user never opened themselves.
      local function surface_edited_file()
        local pending = edited
        edited = nil
        if not pending or not vim.api.nvim_buf_is_valid(pending.buf) then return end
        if not vim.bo[pending.buf].modified then return end
        if #vim.fn.win_findbuf(pending.buf) > 0 then return end

        vim.schedule(function()
          vim.api.nvim_win_set_buf(0, pending.buf)
          pcall(vim.api.nvim_win_set_cursor, 0, pending.position)
        end)
      end

      -- The preview holds a real buffer now, so these maps are buffer-local and
      -- dropped the moment it loses focus -- they must not leak into normal editing.
      local function map_return_to_prompt(preview_winid)
        local buf = vim.api.nvim_get_current_buf()
        for key in pairs(focus_directions) do
          vim.keymap.set('n', '<C-' .. key .. '>', focus_prompt, { buffer = buf, nowait = true })
        end

        vim.api.nvim_create_autocmd('WinLeave', {
          once = true,
          callback = function()
            if edited and vim.api.nvim_get_current_win() == preview_winid then
              edited.position = vim.api.nvim_win_get_cursor(preview_winid)
            end

            for key in pairs(focus_directions) do
              pcall(vim.keymap.del, 'n', '<C-' .. key .. '>', { buffer = buf })
            end
          end,
        })
      end

      local function focus_preview(key)
        return function()
          local win = require('fzf-lua.win').__SELF()
          if not win or not win:validate_preview()
              or win:normalize_preview_layout().pos ~= focus_directions[key] then
            return vim.api.nvim_chan_send(vim.b.terminal_job_id, fzf_control_bytes[key])
          end

          local preview_winid = win.preview_winid
          vim.api.nvim_set_current_win(preview_winid)
          show_real_file_in_preview(preview_winid)
          map_return_to_prompt(preview_winid)
        end
      end

      -- --multi is off for files/lsp/grep: with it on, a >1 selection on <CR>
      -- runs file_edit_or_qf and dumps the paths into a quickfix window instead
      -- of just opening the one entry.
      require('fzf-lua').setup({
        fzf_opts = { ['--cycle'] = true, ['-i'] = true },
        winopts = { on_close = surface_edited_file },
        keymap = {
          fzf = {
            true,
            ['tab']       = 'down',
            ['shift-tab'] = 'up',
            ['alt-p']     = 'prev-history',
            ['alt-n']     = 'next-history',
            ['ctrl-p']    = 'up',
            ['ctrl-n']    = 'down',
          },
        },
        files = {
          fd_opts = '--type f --color=never --hidden --exclude .git',  -- honours .gitignore, no symlink chasing
          fzf_opts = { ['--multi'] = false, ['--cycle'] = true },
        },
        lsp = {
          fzf_opts = { ['--multi'] = false, ['--cycle'] = true },
        },
        grep = {
          fzf_opts = { ['--multi'] = false, ['--cycle'] = true },
          rg_opts = '--column --line-number --no-heading --color=always '
            .. '--ignore-case --hidden --glob=!.git/ --max-columns=4096 -e',
        },
      })

      vim.api.nvim_create_autocmd('FileType', {
        pattern = 'fzf',
        callback = function(args)
          local function send(bytes)
            return function() vim.api.nvim_chan_send(vim.b.terminal_job_id, bytes) end
          end

          vim.keymap.set('t', '<M-[>', send('\27p'), { buffer = args.buf, nowait = true })
          vim.keymap.set('t', '<M-]>', send('\27n'), { buffer = args.buf, nowait = true })

          for key in pairs(focus_directions) do
            vim.keymap.set('t', '<C-' .. key .. '>', focus_preview(key),
              { buffer = args.buf, nowait = true })
          end
        end,
      })

      -- Work around an upstream fzf-lua crash: the builtin previewer's grep match
      -- highlighter calls vim.regex:match_line() with a start byte past the
      -- previewed line's length (ripgrep can report a match column past the
      -- line's end), which raises "invalid start" and kills the preview. Wrap the
      -- regex object so match_line swallows that error and returns nil -- the same
      -- graceful fallback (plain cursor highlight) the previewer already uses.
      -- Monkey-patch so it survives plugin updates; remove if fixed upstream.
      local utils = require('fzf-lua.utils')
      local orig_vim_regex = utils.vim_regex
      utils.vim_regex = function(re, opts)
        local reg = orig_vim_regex(re, opts)
        if not reg then return reg end
        return setmetatable({}, {
          __index = function(_, key)
            if key == 'match_line' then
              return function(_, ...)
                local ok, s, e = pcall(reg.match_line, reg, ...)
                if ok then return s, e end
                return nil
              end
            end
            local v = reg[key]
            if type(v) == 'function' then
              return function(_, ...) return v(reg, ...) end
            end
            return v
          end,
        })
      end
    end,
  },

  -- Project-wide interactive find & replace (ripgrep-backed).
  {
    'MagicDuck/grug-far.nvim',
    cmd = 'GrugFar',
    keys = {
      { '<leader>fr', '<cmd>GrugFar<cr>', desc = 'Find & replace (project)' },
      { '<leader>fr', ":<C-u>lua require('grug-far').with_visual_selection()<CR>",
        mode = 'x', desc = 'Find & replace (selection)' },
    },
    opts = { prefills = { flags = '--ignore-case' } },
  },

  -- The `main` branch: `master` caps below Neovim 0.12 and crashes its query
  -- engine. On `main`, parser install is explicit and highlighting is native via
  -- vim.treesitter.start(). Needs the tree-sitter CLI + a C compiler.
  {
    'nvim-treesitter/nvim-treesitter',
    branch = 'main',
    lazy = false,        -- the main branch does not support lazy-loading
    build = ':TSUpdate',
    config = function()
      -- markdown needs BOTH parsers: block structure + inline spans.
      require('nvim-treesitter').install({
        'c', 'cpp', 'c_sharp', 'lua', 'python', 'rust', 'bash', 'json',
        'markdown', 'markdown_inline',
        'html', 'css', 'scss', 'javascript', 'typescript', 'tsx',
      })

      -- `main` doesn't auto-enable highlighting; turn it on per-filetype, skipping
      -- huge generated files.
      vim.api.nvim_create_autocmd('FileType', {
        pattern = { 'c', 'cpp', 'cs', 'lua', 'python', 'rust', 'sh', 'bash', 'json',
                    'markdown', 'html', 'css', 'scss', 'javascript', 'javascriptreact',
                    'typescript', 'typescriptreact' },
        callback = function(ev)
          local name = vim.api.nvim_buf_get_name(ev.buf)
          local ok, stats = pcall((vim.uv or vim.loop).fs_stat, name)
          if ok and stats and stats.size > 256 * 1024 then return end
          pcall(vim.treesitter.start)
        end,
      })
    end,
  },

  {
    'nvim-treesitter/nvim-treesitter-context',
    event = 'VeryLazy',
    opts = {
      mode = 'cursor',
      max_lines = 0,
      multiline_threshold = 1,    -- collapse each scope to its header line
      trim_scope = 'outer',
      separator = nil,
    },
  },

  { 'neovim/nvim-lspconfig' },

  -- mason fetches language-server binaries into a private dir on Neovim's PATH,
  -- so pyright / rust-analyzer aren't installed system-wide. clangd is
  -- deliberately excluded -- on the Chromium tree we use the version-matched tree
  -- clangd (see local override).
  { 'williamboman/mason.nvim', opts = {} },
  {
    'williamboman/mason-lspconfig.nvim',
    dependencies = { 'williamboman/mason.nvim', 'neovim/nvim-lspconfig' },
    opts = {
      ensure_installed = {
        'pyright', 'rust_analyzer', 'omnisharp',
        'ts_ls', 'html', 'cssls', 'jsonls', 'eslint', 'emmet_language_server',
      },
    },
  },

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
          ['<C-Space>'] = cmp.mapping.complete(),
          ['<CR>']      = cmp.mapping.confirm({ select = true }),
          ['<Tab>']     = cmp.mapping.select_next_item(),
          ['<S-Tab>']   = cmp.mapping.select_prev_item(),
          ['<C-f>']     = cmp.mapping.scroll_docs(4),
          ['<C-b>']     = cmp.mapping.scroll_docs(-4),
        }),
        sources = { { name = 'nvim_lsp' }, { name = 'luasnip' } },
        sorting = {
          comparators = {
            cmp.config.compare.offset,
            cmp.config.compare.exact,
            cmp.config.compare.sort_text,
            cmp.config.compare.score,
            cmp.config.compare.recently_used,
            cmp.config.compare.locality,
            cmp.config.compare.kind,
            cmp.config.compare.length,
            cmp.config.compare.order,
          },
        },
        formatting = {
          fields = { 'abbr', 'kind', 'menu' },
          format = function(entry, item)
            local ci = entry.completion_item
            local ld = ci.labelDetails
            local ctx
            if ld and ld.detail and ld.detail:match('^%s*%(as ') then
              ctx = ld.detail
            else
              ctx = (ld and ld.description) or ci.detail
            end
            if ctx and ctx ~= '' then
              ctx = ctx:gsub('%s+', ' ')
              if #ctx > 40 then ctx = ctx:sub(1, 39) .. '…' end
              item.menu = ctx
            end
            return item
          end,
        },
      })
    end,
  },

  {
    'ray-x/lsp_signature.nvim',
    event = 'LspAttach',
    opts = {
      hint_enable = false,
      floating_window = true,
      floating_window_above_cur_line = true,
      -- Only pop on the `(`/`,` trigger chars. The default idle-refresh (CursorHold)
      -- re-requests signature help while you rest on a line, which surfaces stale /
      -- enclosing-call hints on blank lines.
      cursorhold_update = false,
      toggle_key = '<C-s>',   -- also summon/dismiss on demand in insert mode
    },
  },

  -- Copilot ghost text. Accept is <C-l>, NOT <Tab> (that's nvim-cmp's select-next
  -- above), so the two completion systems don't fight.
  {
    'zbirenbaum/copilot.lua',
    cmd = 'Copilot',
    event = 'InsertEnter',
    opts = {
      suggestion = {
        auto_trigger = true,
        keymap = {
          accept = '<C-l>',
          next = '<M-]>',
          prev = '<M-[>',
          dismiss = '<C-]>',
        },
      },
      panel = { enabled = false },
    },
  },

  {
    'lewis6991/gitsigns.nvim',
    opts = {
      current_line_blame = true,  -- GitLens-style eol ghost text; toggle with <leader>gB
      current_line_blame_opts = { delay = 250, virt_text_pos = 'eol' },
    },
  },
  { 'tpope/vim-fugitive' },

  -- default_mappings is OFF because its defaults grab `ct`, which is the vim
  -- change-till operator; we bind our own conflict keys in config/git.lua.
  {
    'akinsho/git-conflict.nvim',
    version = '*',
    opts = { default_mappings = false },
  },

  -- map_cr = false leaves <CR> to nvim-cmp (accept completion).
  {
    'windwp/nvim-autopairs',
    event = 'InsertEnter',
    config = function()
      require('nvim-autopairs').setup({ map_cr = false })
      -- Insert () after confirming a function/method from cmp. On InsertEnter so
      -- both cmp and autopairs are loaded; registered once.
      local ok, cmp = pcall(require, 'cmp')
      if ok then
        cmp.event:on('confirm_done',
          require('nvim-autopairs.completion.cmp').on_confirm_done())
      end
    end,
  },
}, {
  ui = { border = 'rounded' },
})
