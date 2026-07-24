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
    config = function() vim.cmd.colorscheme('tokyonight-night') end,
  },

  {
    'nvim-lualine/lualine.nvim',
    -- globalstatus matches the topbar's forced laststatus=3, so no per-window
    -- statusline is drawn as an extra row under the reserved topbar window.
    opts = {
      options = { theme = 'tokyonight', globalstatus = true },
      sections = { lualine_c = { { 'filename', path = 1 } } },  -- path relative to cwd
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

      -- --multi is off for files/lsp/grep: with it on, a >1 selection on <CR>
      -- runs file_edit_or_qf and dumps the paths into a quickfix window instead
      -- of just opening the one entry.
      require('fzf-lua').setup({
        fzf_opts = { ['--cycle'] = true, ['-i'] = true },
        keymap = {
          fzf = {
            true,
            ['tab']       = 'down',
            ['shift-tab'] = 'up',
            ['alt-[']     = 'prev-history',
            ['alt-]']     = 'next-history',
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
      })

      -- `main` doesn't auto-enable highlighting; turn it on per-filetype, skipping
      -- huge generated files.
      vim.api.nvim_create_autocmd('FileType', {
        pattern = { 'c', 'cpp', 'cs', 'lua', 'python', 'rust', 'sh', 'bash', 'json',
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
    opts = { ensure_installed = { 'pyright', 'rust_analyzer', 'omnisharp' } },
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
