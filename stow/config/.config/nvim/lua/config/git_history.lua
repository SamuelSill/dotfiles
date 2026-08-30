-- config/git_history.lua -- fzf-lua pickers over `git log` for a file or a line
-- range, and jump-to-pull-request for a commit.
-- Fugitive's `:Git log` is not used for these: it folds a `-L` walk into a
-- single quickfix entry, so only the most recent commit is reachable.

local RECORD_SEP, FIELD_SEP = '\30', '\31'
local LOG_FORMAT = RECORD_SEP .. '%H' .. FIELD_SEP ..
  '%C(yellow)%h%C(reset) %C(green)%as%C(reset) %C(blue)%<(20,trunc)%an%C(reset) %s'

local M = {}

local function git(cwd, args)
  local result = vim.system(vim.list_extend({ 'git', '--no-pager' }, args), { cwd = cwd, text = true }):wait()
  if result.code ~= 0 then
    return nil, vim.trim(result.stderr ~= '' and result.stderr or result.stdout)
  end

  return result.stdout
end

-- One entry per commit, newest first, reported as the log produces them.
-- Whatever the log prints after each commit's header line (a patch, if the
-- caller asked for one) becomes its body.
-- Streaming rather than waiting for the whole walk matters on huge repos: in
-- chromium a path-limited walk takes tens of seconds, and the wanted commits
-- are the first ones out.
local function stream_commits(cwd, log_args, on_commit, on_done)
  local pending, count = '', 0

  local function emit(record)
    local sha, header, body = record:match('^(%x+)' .. FIELD_SEP .. '([^\n]*)\n(.*)$')
    if sha then
      count = count + 1
      on_commit({ sha = sha, header = header, body = vim.trim(body) })
    end
  end

  -- The format prefixes every record with RECORD_SEP, so the trailing piece of
  -- a chunk is always an unfinished record (or the leading empty one).
  local function consume(chunk)
    pending = pending .. chunk
    local records = vim.split(pending, RECORD_SEP, { plain = true })
    pending = table.remove(records)
    vim.tbl_map(emit, records)
  end

  local args = vim.list_extend({ 'git', '--no-pager', 'log', '--color=always', '--format=' .. LOG_FORMAT }, log_args)
  vim.system(args, {
    cwd = cwd,
    text = true,
    stdout = function(_, data) if data then vim.schedule(function() consume(data) end) end end,
  }, function(result)
    vim.schedule(function()
      emit(pending)
      on_done(count, result.code ~= 0 and vim.trim(result.stderr) or nil)
    end)
  end)
end

local function abbrev_sha(line)
  return require('fzf-lua.utils').strip_ansi_coloring(line):match('^%x+')
end

function M.browse_pull_request(cwd, sha)
  if vim.fn.executable('gh') == 0 then
    vim.notify('gh is not installed', vim.log.levels.ERROR)
    return
  end

  local args = { 'gh', 'api', 'repos/{owner}/{repo}/commits/' .. sha .. '/pulls', '--jq', '.[0].html_url' }
  vim.system(args, { cwd = cwd, text = true }, vim.schedule_wrap(function(result)
    local url = vim.trim(result.stdout or '')
    if result.code ~= 0 or url == '' or url == 'null' then
      vim.notify('No pull request found for ' .. sha, vim.log.levels.WARN)
      return
    end

    vim.fn.setreg('+', url)
    vim.ui.open(url)
    vim.notify(url)
  end))
end

-- git is run from the file's own directory so these work in whatever repo the
-- buffer belongs to, regardless of nvim's cwd.
local function buffer_target()
  local file = vim.fn.expand('%:p')
  if file == '' then
    vim.notify('Buffer is not backed by a file', vim.log.levels.WARN)
    return nil
  end

  return vim.fn.fnamemodify(file, ':h'), vim.fn.fnamemodify(file, ':t')
end

local function pick(prompt, cwd, log_args, preview_body)
  local by_sha = {}

  local function contents(fzf_cb)
    stream_commits(cwd, log_args, function(commit)
      by_sha[abbrev_sha(commit.header)] = commit
      fzf_cb(commit.header)
    end, function(count, err)
      fzf_cb()
      if err then
        vim.notify(err, vim.log.levels.ERROR)
      elseif count == 0 then
        vim.notify('No history found', vim.log.levels.WARN)
      end
    end)
  end

  local function on_commit(action)
    return function(selected)
      local commit = by_sha[abbrev_sha(selected[1])]
      if commit then action(commit) end
    end
  end

  require('fzf-lua').fzf_exec(contents, {
    prompt = prompt,
    fzf_opts = { ['--ansi'] = true },
    preview = function(items)
      local commit = by_sha[abbrev_sha(items[1])]
      return commit and vim.split(preview_body(commit), '\n') or {}
    end,
    -- `header` on each action makes fzf-lua print the cheatsheet line inside
    -- the picker -- the topbar can't be seen from behind fzf's float.
    actions = {
      ['default'] = {
        header = 'open commit',
        fn = on_commit(function(commit) vim.cmd('tab Gedit ' .. commit.sha) end),
      },
      ['ctrl-k'] = {
        header = 'open pull request',
        fn = on_commit(function(commit) M.browse_pull_request(cwd, commit.sha) end),
      },
      ['ctrl-y'] = {
        header = 'yank sha',
        fn = on_commit(function(commit)
          vim.fn.setreg('+', commit.sha)
          vim.notify('Yanked ' .. commit.sha)
        end),
      },
    },
  })
end

local function open_picker(prompt, log_args, preview_body)
  local cwd, name = buffer_target()
  if not cwd then return end

  pick(prompt, cwd, log_args(name), function(commit) return preview_body(cwd, name, commit) end)
end

-- The `-L` walk is the only source of a range-scoped diff, so its patches are
-- taken from the log's own output and previewed as-is.
function M.line(first, last)
  open_picker(
    string.format('Lines %d-%d> ', first, last),
    function(name) return { string.format('-L%d,%d:%s', first, last, name) } end,
    function(_, _, commit) return commit.body end)
end

-- Whole-file patches are too big to carry in the log output, so previews are
-- rendered on demand instead.
function M.file()
  open_picker(
    'File history> ',
    function(name) return { '--follow', '--', name } end,
    function(cwd, name, commit)
      return git(cwd, { 'show', '--color=always', commit.sha, '--', name }) or ''
    end)
end

-- Skips the picker: goes straight to the pull request of whichever commit
-- blame attributes the line to.
function M.pull_request_for_line(lnum)
  local cwd, name = buffer_target()
  if not cwd then return end

  local out, err = git(cwd, { 'blame', '-L', string.format('%d,%d', lnum, lnum), '--porcelain', '--', name })
  if not out then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  local sha = out:match('^(%x+)')
  if not sha or sha:match('^0+$') then
    vim.notify('Line is not committed yet', vim.log.levels.WARN)
    return
  end

  M.browse_pull_request(cwd, sha)
end

-- For fugitive's blame column, where each line already starts with its sha
-- ('^' marks a boundary commit).
function M.pull_request_for_blame_line()
  local sha = vim.api.nvim_get_current_line():match('^%^?(%x+)')
  if not sha or sha:match('^0+$') then
    vim.notify('Line is not committed yet', vim.log.levels.WARN)
    return
  end

  M.browse_pull_request(vim.fn.FugitiveWorkTree(), sha)
end

return M
