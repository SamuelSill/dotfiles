-- config/keymaps.lua -- global (non-LSP, non-git) keymaps: finders, navigation,
-- editing helpers, and the custom change-case / surround / substitute operators.
-- Git maps live in config/git.lua; buffer-local LSP maps in config/lsp.lua.

local map = vim.keymap.set
local fzf = require('fzf-lua')
local lsp = require('config.lsp')
local ai = require('config.ai')

map('n', '<leader>e',  '<cmd>NvimTreeFindFileToggle<cr>', { desc = 'Explorer (reveal current file)' })
map('n', '<M-d>', lsp.smart_goto_definition, { desc = 'Goto definition / file under cursor' })
map('n', '<M-r>', lsp.smart_references, { desc = 'Goto references' })

-- Find-files with recently-visited files floated to the top: prepend this cwd's
-- :oldfiles entries to fd's stream, dedupe (recents win), and break fzf score
-- ties by input order (--tiebreak=index) so a recent match outranks an equally
-- good non-recent one. fd still streams, so it stays fast on huge trees.
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
  local cmd = '{ ' .. prepend .. find .. "; } | awk '!seen[$0]++'"  -- awk keeps the first (recent) occurrence
  fzf.files({ cmd = cmd, fzf_opts = { ['--tiebreak'] = 'index', ['--multi'] = false } })
end
map('n', '<C-p>',      find_files_recent_first,  { desc = 'Find files (recent first)' })
map('n', '<leader>ff', find_files_recent_first,  { desc = 'Find files (recent first)' })
-- Grep supports a trailing ` -- <glob>` file filter, e.g.  TODO -- *.{h,cc} !*test*
map('n', '<leader>fg', fzf.live_grep,            { desc = 'Grep in project (+ file glob)' })
map('x', '<leader>fg', fzf.grep_visual,          { desc = 'Grep selection in project' })
map('n', '<leader>fs', fzf.lsp_live_workspace_symbols, { desc = 'Find symbol in project (#)' })
map('n', '<leader>fS', fzf.lsp_document_symbols,       { desc = 'Find symbol in current file (@)' })
map('n', '<leader>fb', fzf.buffers,              { desc = 'Open buffers' })
map('n', '<leader>fh', fzf.helptags,             { desc = 'Help tags' })
-- Jumplist back/forward: alt-[ / alt-] alias <C-o>/<C-i>.
map('n', '<M-[>', '<C-o>', { desc = 'Jump back' })
map('n', '<M-]>', '<C-i>', { desc = 'Jump forward' })

do
  -- Declaration node types (not their bodies) across common grammars.
  local BLOCK = {
    function_item = true, function_definition = true, function_declaration = true,
    method_definition = true, method_declaration = true, constructor_declaration = true,
    local_function = true, arrow_function = true, function_expression = true,
    struct_item = true, struct_specifier = true, struct_declaration = true,
    class_declaration = true, class_definition = true, class_specifier = true,
    enum_item = true, enum_specifier = true, enum_declaration = true,
    union_item = true, union_specifier = true,
    interface_declaration = true, trait_item = true,
    namespace_definition = true, mod_item = true, module = true,
    impl_item = true, type_item = true, type_alias_declaration = true,
    type_definition = true, macro_definition = true,
  }
  -- Most grammars expose a `name` field; rust `impl` names a target type instead;
  -- C/C++ nest the name down the declarator chain.
  local function name_node(node)
    if node:type():find('impl', 1, true) then
      return node:field('type')[1] or node:field('trait')[1]
    end
    local named = node:field('name')[1]
    if named then return named end
    local decl = node:field('declarator')[1]
    while decl do
      local t = decl:type()
      if t == 'qualified_identifier' then                   -- C++ Foo::bar → bar
        return decl:field('name')[1] or decl
      elseif t:find('identifier', 1, true) or t == 'operator_name' or t == 'destructor_name' then
        return decl
      end
      decl = decl:field('declarator')[1]
    end
    return nil
  end
  local function node_at_cursor()
    local ok, node = pcall(vim.treesitter.get_node)
    return ok and node or nil
  end
  map('n', '<M-b>', function()
    local node = node_at_cursor()
    if not node then                                        -- tree not parsed yet
      pcall(function() vim.treesitter.get_parser():parse() end)
      node = node_at_cursor()
    end
    local cur_r, cur_c = unpack(vim.api.nvim_win_get_cursor(0))
    cur_r = cur_r - 1
    while node do
      if BLOCK[node:type()] then
        local r, c = (name_node(node) or node):start()
        if r < cur_r or (r == cur_r and c < cur_c) then       -- only jump backwards; else seek outer block
          vim.cmd("normal! m'")                                -- record jump for <C-o>
          vim.api.nvim_win_set_cursor(0, { r + 1, c })
          vim.cmd('normal! zz')
          return
        end
      end
      node = node:parent()
    end
    vim.notify('No enclosing block', vim.log.levels.INFO)
  end, { desc = 'Jump to enclosing block name (fn/class/struct/…)' })
end

map('n', '<C-h>', '<C-w>h', { desc = 'Focus window left' })
map('n', '<C-j>', '<C-w>j', { desc = 'Focus window below' })
map('n', '<C-k>', '<C-w>k', { desc = 'Focus window above' })
map('n', '<C-l>', '<C-w>l', { desc = 'Focus window right' })
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
map('n', '<leader>yl', function()
  local rel = vim.fn.expand('%:.') .. ':' .. vim.fn.line('.')
  vim.fn.setreg('+', rel)
  vim.notify('Copied path: ' .. rel)
end, { desc = 'Copy relative path with line number' })
map('n', '<leader>yL', function()
  local abs = vim.fn.expand('%:p') .. ':' .. vim.fn.line('.')
  vim.fn.setreg('+', abs)
  vim.notify('Copied path: ' .. abs)
end, { desc = 'Copy full (absolute) path with line number' })
map('x', 'p', 'P', { desc = 'Paste over selection without yanking it' })
map('n', '<leader>w',  '<cmd>write<cr>',         { desc = 'Save file' })
map('n', '<leader>q',  '<cmd>quit<cr>',          { desc = 'Quit window' })
map('n', '<Esc>',      '<cmd>nohlsearch<cr>',    { desc = 'Clear search highlight' })

-- H toggles between the first non-blank char (^) and column 0, depending on where
-- the cursor sits relative to the indent. expr = true so one mapping serves
-- normal/visual/operator-pending (e.g. dL, yH).
local function smart_home()
  local col = vim.fn.col('.')
  local first_non_blank = vim.fn.match(vim.fn.getline('.'), '\\S') + 1  -- 0 if line is all blank
  if first_non_blank == 0 then return '0' end
  if col == 1 then return '^' end
  if col <= first_non_blank then return '0' end
  return '^'
end
map({ 'n', 'x', 'o' }, 'H', smart_home, { expr = true, desc = 'Start of line (smart: non-blank, else col 0)' })
map({ 'n', 'x', 'o' }, 'L', '$', { desc = 'End of line (like $)' })

-- Live selection as 0-indexed (sr, sc, er, ec), ec exclusive and multibyte-safe.
-- Reads getpos('v')/getpos('.'), not the '</'> marks, which only update on
-- leaving visual mode (mid-mapping they'd point at the previous selection).
local function visual_range()
  local a, b = vim.fn.getpos('v'), vim.fn.getpos('.')
  if a[2] > b[2] or (a[2] == b[2] and a[3] > b[3]) then a, b = b, a end
  local sr, sc, er, ec = a[2] - 1, a[3] - 1, b[2] - 1, b[3] - 1
  local last = vim.api.nvim_buf_get_lines(0, er, er + 1, true)[1]
  ec = math.min(ec, #last - 1)                         -- clamp $-past-EOL / v:maxcol
  ec = ec + #(vim.fn.matchstr(last:sub(ec + 1), '.'))  -- inclusive → exclusive
  return sr, sc, er, ec
end

do
  local function split_words(s)
    s = s:gsub('(%l)(%u)', '%1 %2')      -- camelCase boundary:  fooBar → foo Bar
    s = s:gsub('(%u)(%u%l)', '%1 %2')    -- acronym boundary:    HTTPServer → HTTP Server
    s = s:gsub('[%-_%s]+', ' ')
    local words = {}
    for w in s:gmatch('%S+') do words[#words + 1] = w:lower() end
    return words
  end

  local function cap(w) return w:sub(1, 1):upper() .. w:sub(2) end

  local styles = {
    { name = 'PascalCase', fn = function(w)
        local out = {} for _, x in ipairs(w) do out[#out + 1] = cap(x) end
        return table.concat(out)
      end },
    { name = 'camelCase', fn = function(w)
        local out = {} for i, x in ipairs(w) do out[#out + 1] = i == 1 and x or cap(x) end
        return table.concat(out)
      end },
    { name = 'snake_case',  fn = function(w) return table.concat(w, '_') end },
    { name = 'CONST_CASE',  fn = function(w) return table.concat(w, '_'):upper() end },
    { name = 'kebab-case',  fn = function(w) return table.concat(w, '-') end },
  }

  local function change_case()
    local sr, sc, er, ec = visual_range()
    local words = split_words(table.concat(vim.api.nvim_buf_get_text(0, sr, sc, er, ec, {}), ' '))
    if #words == 0 then return end

    vim.ui.select(styles, {
      prompt = 'Change case:',
      format_item = function(item) return item.fn(words) .. '   (' .. item.name .. ')' end,
    }, function(choice)
      if not choice then return end
      vim.api.nvim_buf_set_text(0, sr, sc, er, ec, { choice.fn(words) })
    end)
  end

  map('x', '<A-c>', change_case, { desc = 'Change case of selection (Pascal/camel/snake/CONST/kebab)' })
end

do
  local brackets = {
    ['('] = { '(', ')' }, [')'] = { '(', ')' },
    ['['] = { '[', ']' }, [']'] = { '[', ']' },
    ['{'] = { '{', '}' }, ['}'] = { '{', '}' },
    ['<'] = { '<', '>' }, ['>'] = { '<', '>' },
    ['"'] = { '"', '"' }, ["'"] = { "'", "'" }, ['`'] = { '`', '`' },
  }

  local function surround()
    local sr, sc, er, ec = visual_range()
    local ok, ch = pcall(vim.fn.getcharstr)
    if not ok or ch == '' or ch == vim.keycode('<Esc>') then return end
    local pair = brackets[ch]
    if not pair then return end
    local open, close = pair[1], pair[2]

    local lines = vim.api.nvim_buf_get_text(0, sr, sc, er, ec, {})
    lines[1] = open .. lines[1]
    lines[#lines] = lines[#lines] .. close
    vim.api.nvim_buf_set_text(0, sr, sc, er, ec, lines)
    vim.api.nvim_feedkeys(vim.keycode('<Esc>'), 'n', false)
  end

  map('x', 's', function() surround() end, { desc = "Surround selection tight: s then ( { [ < \" ' `" })
end

map({ 'n', 'x' }, '<M-a>', ai.ask, { desc = 'Ask claude about line / selection' })

map('n', '<leader>?', fzf.keymaps, { desc = 'Show all keybindings' })

map('n', '<leader>dv', function()
  local on = vim.diagnostic.config().virtual_text
  vim.diagnostic.config({ virtual_text = not on })
  vim.notify('Inline diagnostics ' .. (on and 'OFF' or 'ON'))
end, { desc = 'Toggle inline diagnostics (virtual text)' })

map('n', '<leader>s', [[:%s/\<<C-r><C-w>\>/]], { desc = 'Substitute word under cursor (file)' })
map('x', '<A-s>', function()
  local m = vim.fn.mode()
  local text = table.concat(vim.fn.getregion(vim.fn.getpos('v'), vim.fn.getpos('.'), { type = m }), '\n')
  local pat = text:gsub('\\', '\\\\'):gsub('/', '\\/'):gsub('\n', '\\n')
  -- <C-u> clears the '<,'> that ':' prefills, so the substitute spans the whole
  -- file. pat is fed raw (not via replace_termcodes) so a literal '<' stays literal.
  vim.api.nvim_feedkeys(':' .. vim.keycode('<C-u>') .. '%s/\\V' .. pat .. '/', 'n', false)
end, { desc = 'Substitute selection (file)' })

-- Disable arrow keys.
for _, k in ipairs({ '<Up>', '<Down>', '<Left>', '<Right>' }) do
  map({ 'n', 'i', 'v' }, k, '<Nop>', { silent = true })
end
