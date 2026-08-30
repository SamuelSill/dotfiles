-- config/recent_files.lua -- per-project list of recently visited files, used by
-- <C-p> to float recents to the top of the finder.
--
-- Neovim's own v:oldfiles is one global, shada-backed list, so files from a busy
-- checkout evict every other checkout's. This keeps a separate list per project
-- root (the nearest .git, else the cwd), persisted under stdpath('state'), so a
-- project's recents survive both restarts and work done on other trees.

local M = {}

local MAX_ENTRIES = 200
local store_dir = vim.fn.stdpath('state') .. '/recent-files'

local recent = {}
local loaded_root = nil
local roots = {}

local function project_root()
  local cwd = vim.uv.cwd()
  if not roots[cwd] then
    roots[cwd] = vim.fs.root(cwd, '.git') or cwd
  end

  return roots[cwd]
end

local function store_path()
  return store_dir .. '/' .. loaded_root:gsub('/', '%%')
end

local function read_stored()
  local ok, lines = pcall(vim.fn.readfile, store_path())

  return ok and lines or {}
end

-- Most-recent-first, deduped (first occurrence wins), capped.
local function merged(first, second)
  local seen, out = {}, {}
  for _, list in ipairs({ first, second }) do
    for _, file in ipairs(list) do
      if not seen[file] and #out < MAX_ENTRIES then
        seen[file] = true
        out[#out + 1] = file
      end
    end
  end

  return out
end

-- :cd into another project swaps which list we're reading and writing.
local function load_for_current_project()
  local root = project_root()
  if loaded_root == root then return end

  loaded_root = root
  recent = read_stored()
end

-- Saving on every visit, rather than on VimLeavePre, because a closed Zellij pane
-- SIGHUPs Neovim and exit autocmds never run (see the swap-file note in options).
local function save()
  vim.fn.mkdir(store_dir, 'p')
  -- Fold the on-disk list back in so a second Neovim open on the same project
  -- doesn't lose what it recorded while we were running.
  vim.fn.writefile(merged(recent, read_stored()), store_path())
end

local function record(file)
  load_for_current_project()
  recent = merged({ file }, recent)
  save()
end

--- Recently visited files in the current project, most recent first.
function M.list()
  load_for_current_project()

  return recent
end

vim.api.nvim_create_autocmd('BufEnter', {
  group = vim.api.nvim_create_augroup('recent_files', { clear = true }),
  callback = function(args)
    if vim.bo[args.buf].buftype ~= '' then return end
    local file = vim.api.nvim_buf_get_name(args.buf)
    if file ~= '' then record(file) end
  end,
})

return M
