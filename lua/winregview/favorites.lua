local M = {}

---@type string[] entries
M.entries = {}

M.favpath = vim.fn.stdpath('state') .. '/winregview_favorites.txt'

local function find_index(table, to_find)
  for index, value in ipairs(table) do
    if value == to_find then
      return index
    end
  end
  return nil
end

---@param uri winreg.bufinfo
function M.add(uri)
  local core = require('winregview.core')
  --local normalized = assert(core.normalize_reg_path(uri))
  table.insert(M.entries, uri)
  M.persist()
end

---@param uri winreg.bufinfo
function M.remove(uri)
  local idx = find_index(M.entries, uri)
  if not idx then
    return
  end
  table.remove(M.entries, idx)
  M.persist()
end

function M.print()
  vim.print(vim.inspect(M.entries))
end

function M.toggle_buf(buf)
  buf = buf or 0

  ---@type winreg.bufinfo
  local bufinfo = vim.b[buf].winreg
  assert(bufinfo, 'buffer must be a registry buffer')
  if M.is_buf_fav(buf) then
    M.remove(bufinfo.uri)
    print('removed from favorites')
  else
    M.add(bufinfo.uri)
    print('added to favorites')
  end
end

function M.is_buf_fav(buf)
  local uri = vim.b[buf or 0].winreg.uri
  return vim.tbl_contains(M.entries, uri)
end

function M.persist()
  local contents = table.concat(M.entries, '\n')
  local f = assert(io.open(M.favpath, "wb"))
  f:write(contents)
  f:close()
end

function M.load()
  print('fav-file reloaded')
  if not vim.uv.fs_stat(M.favpath) then
    return
  end
  M.entries = {}
  for value in io.lines(M.favpath) do
      table.insert(M.entries, value)
  end
end

M.load()

vim.api.nvim_create_user_command('WinRegToggleFav', function() M.toggle_buf() end, {})
vim.api.nvim_create_user_command('WinRegEditFavs', function()
  vim.cmd(":e " .. M.favpath)
end, {})

vim.api.nvim_create_autocmd('BufWritePost', {
  pattern = vim.fs.normalize(M.favpath),
  callback = M.load
})

vim.api.nvim_create_user_command('WinRegToggleFav', function(_) M.toggle_buf() end, {})

return M
