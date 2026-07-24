-- config/ai.lua -- ask Claude a question about the current line / visual
-- selection, headless (`claude -p`), answer shown in a scratch float. Strictly
-- read-only Q&A: no session, no edits, no diffs -- for changes, run claude in a
-- terminal. The keymap lives in config/keymaps.lua.

local M = {}

local function float(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = 'markdown'
  vim.bo[buf].modifiable = false
  local width = math.min(100, math.floor(vim.o.columns * 0.8))
  local height = math.min(#lines + 1, math.floor(vim.o.lines * 0.8))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal',
    border = 'rounded',
    title = ' claude ',
  })
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  for _, k in ipairs({ 'q', '<Esc>' }) do
    vim.keymap.set('n', k, '<cmd>close<cr>', { buffer = buf, nowait = true })
  end
end

-- Line range for the mapping: the visual selection when called from visual mode,
-- else the cursor line. Reads getpos('v')/('.') because the '</'> marks only
-- update on leaving visual mode; drop back to normal so the buffer settles.
local function range()
  local mode = vim.fn.mode()
  if mode:match('[vV\22]') then
    local s, e = vim.fn.getpos('v')[2], vim.fn.getpos('.')[2]
    -- 'x' flushes the <Esc> synchronously; queued, the vim.ui.input prompt below
    -- would swallow it as a cancel and the whole thing would silently no-op.
    vim.api.nvim_feedkeys(vim.keycode('<Esc>'), 'nx', false)
    if s > e then s, e = e, s end
    return s, e
  end
  local l = vim.fn.line('.')
  return l, l
end

function M.ask()
  local sr, er = range()
  local path = vim.fn.expand('%:.')
  local code = vim.api.nvim_buf_get_lines(0, sr - 1, er, false)
  local loc = (sr == er) and ('line ' .. sr) or ('lines ' .. sr .. '-' .. er)

  vim.ui.input({ prompt = 'Ask claude about ' .. loc .. ': ' }, function(question)
    if not question or question == '' then return end
    local prompt = table.concat({
      'File: ' .. path .. ' (' .. loc .. ')',
      'Question: ' .. question,
      '',
      'Relevant code:',
      '```',
      table.concat(code, '\n'),
      '```',
    }, '\n')

    vim.notify('Asking claude about ' .. loc .. '…')
    vim.system({ 'claude', '-p' }, { stdin = prompt, text = true }, function(res)
      vim.schedule(function()
        local out = (res.code == 0 and res.stdout ~= '') and res.stdout
          or ('**claude failed** (exit ' .. res.code .. ')\n\n' .. (res.stderr or ''))
        float(vim.split(vim.trim(out), '\n', { plain = true }))
      end)
    end)
  end)
end

return M
