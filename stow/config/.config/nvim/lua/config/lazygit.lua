-- config/lazygit.lua -- lazygit hosted in a full-screen Neovim terminal, so the
-- files it opens land in this instance: plugins and language servers stay warm
-- instead of being reloaded and re-indexed by a fresh editor per file. lazygit
-- reaches back through $NVIM to :LazygitEdit -- see the `os` section of its config.
--
-- The window is a float rather than a tabpage or split: it covers the topbar and
-- statusline (lazygit wants the whole pane) and leaves the window layout untouched.

local M = {}

local COMMAND = 'lazygit'

-- quits_editor: this Neovim was started only to host lazygit (the `lg` alias), so
-- quitting lazygit should hand the pane back to the shell rather than leave an empty
-- editor behind. Not so for the editor pane, which merely opens on the git view.
local state = { buffer = nil, window = nil, quits_editor = false }

local function geometry()
  return {
    relative = 'editor',
    row = 0,
    col = 0,
    width = vim.o.columns,
    height = math.max(vim.o.lines - vim.o.cmdheight, 1),
    style = 'minimal',
    zindex = 200,      -- above the topbar's reserved window
  }
end

local function is_visible()
  return state.window ~= nil and vim.api.nvim_win_is_valid(state.window)
end

local function is_running()
  return state.buffer ~= nil and vim.api.nvim_buf_is_valid(state.buffer)
end

--- Hide lazygit, leaving it running so reopening comes back to the same view.
function M.hide()
  if is_visible() then
    vim.api.nvim_win_close(state.window, true)
  end

  state.window = nil
end

local function on_exit()
  M.hide()
  if is_running() then
    vim.api.nvim_buf_delete(state.buffer, { force = true })
  end

  state.buffer = nil
  if state.quits_editor then
    -- Refuses, harmlessly, on unsaved changes: better to be left in the editor than
    -- to lose them.
    vim.schedule(function() pcall(vim.cmd, 'quitall') end)
  end
end

local function start(options)
  state.quits_editor = options.quits_editor or false
  state.buffer = vim.api.nvim_create_buf(false, true)
  state.window = vim.api.nvim_open_win(state.buffer, true, geometry())
  -- Without 'hide' the job would be killed the moment the window closes, which is
  -- what happens every time lazygit hands a file over.
  vim.bo[state.buffer].bufhidden = 'hide'
  vim.fn.jobstart(vim.list_extend({ COMMAND }, options.arguments or {}),
    { term = true, on_exit = on_exit })
  -- Neither lazygit nor zellij binds <C-x>, so it reaches us here.
  vim.keymap.set({ 'n', 't' }, '<C-x>', M.hide,
    { buffer = state.buffer, desc = 'Hide lazygit (leave it running)' })
end

--- Show lazygit, starting it if it isn't running yet. `options` (start only):
--- quits_editor, and arguments to pass lazygit.
function M.show(options)
  if is_visible() then
    vim.api.nvim_set_current_win(state.window)
  elseif is_running() then
    state.window = vim.api.nvim_open_win(state.buffer, true, geometry())
  else
    start(options or {})
  end

  vim.cmd.startinsert()
end

function M.toggle()
  if is_visible() then
    M.hide()

    return
  end

  M.show()
end

-- A sidebar or terminal window would swallow the file lazygit just handed over.
local function focus_code_window()
  if vim.bo.buftype == '' then return end

  for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(window)].buftype == '' then
      vim.api.nvim_set_current_win(window)

      return
    end
  end
end

-- Not `:edit`: that rereads the file, which fails on unsaved changes -- and the
-- file handed over is often the one just edited.
local function open(path)
  local buffer = vim.fn.bufadd(vim.fn.fnamemodify(path, ':p'))

  vim.fn.bufload(buffer)
  vim.bo[buffer].buflisted = true
  vim.api.nvim_set_current_buf(buffer)
end

--- Open what lazygit asked for: `[+{line}] {path}`, lazygit itself left running
--- behind the file, one toggle away.
function M.edit(argument)
  local line, path = argument:match('^%+(%d+)%s+(.*)$')
  if not line then path = argument end

  M.hide()
  focus_code_window()
  open(path)
  if line then
    vim.api.nvim_win_set_cursor(0, { math.min(tonumber(line), vim.fn.line('$')), 0 })
    vim.cmd('normal! zz')
  end
end

-- With a bang, quitting lazygit quits Neovim with it: `lg` starts an editor for
-- lazygit to live in, and the shell is what you expect back. Arguments go to lazygit.
vim.api.nvim_create_user_command('Lazygit', function(arguments)
  M.show({ quits_editor = arguments.bang, arguments = arguments.fargs })
end, { bang = true, nargs = '*', desc = 'Open lazygit (! to quit Neovim when it exits)' })

vim.api.nvim_create_user_command('LazygitEdit', function(arguments) M.edit(arguments.args) end,
  { nargs = '+', complete = 'file', desc = 'Open a file lazygit asked for' })

vim.api.nvim_create_autocmd('VimResized', {
  group = vim.api.nvim_create_augroup('lazygit_resize', { clear = true }),
  callback = function()
    if is_visible() then
      vim.api.nvim_win_set_config(state.window, geometry())
    end
  end,
})

return M
