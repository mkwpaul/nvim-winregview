_G.winreg = _G.winreg or {}
local augroup_winregview = vim.api.nvim_create_augroup("winregview", { clear = true })

-- Handle viewing registry keys (list subkeys and values)
vim.api.nvim_create_autocmd("BufReadCmd", {
  pattern = "winreg:///key/*",
  group = augroup_winregview,
  callback = function(...)
    require('winregview').bufread_key(...)
  end
})

-- Handle viewing individual registry values
vim.api.nvim_create_autocmd("BufReadCmd", {
  pattern = "winreg:///value/*",
  group = augroup_winregview,
  callback = function(...)
    require('winregview').bufread_value(...)
  end
})


-- User command to open registry paths
vim.api.nvim_create_user_command("WinReg", function(opts)
  local args = opts.fargs
  local reg_path

  if #args == 0 then
    -- No arguments -> show root keys
    reg_path = ""
  else
    -- Join all arguments to support paths with spaces
    reg_path = table.concat(args, " ")
    -- Remove escaped spaces
    reg_path = reg_path:gsub([[\ ]], ' ')
    -- Remove trailing backslash if present
    reg_path = reg_path:gsub('\\$', '')
  end

  local uri = "winreg:///key/" .. reg_path
  vim.cmd("edit " .. vim.fn.fnameescape(uri))
end, {
  nargs = "*",
  desc = "Open Windows Registry view",
  complete = function(arglead, _, _)
    return require('winregview').registry_path_complete(arglead)
  end,
})

-- User command to export the current registry key
---@diagnostic disable-next-line: lowercase-global
function _G.winreg.export_regbuf_as_reg()
  local buf = vim.api.nvim_get_current_buf()
  local reg_path = vim.b[buf].winreg_path

  if not reg_path or reg_path == '' then
    vim.notify('Not in a registry view buffer', vim.log.levels.ERROR)
    return
  end

  -- Create a temporary file for the export
  local temp_file = vim.fn.tempname() .. '.reg'

  -- Export the registry key to the temporary file
  vim.system({ 'reg.exe', 'export', reg_path, temp_file, '/y' }, { text = true }, vim.schedule_wrap(function(result)
    if result.code ~= 0 then
      local err_msg = result.stderr or 'Failed to export registry key'
      vim.notify('reg.exe export failed: ' .. err_msg, vim.log.levels.ERROR)
      return
    end

    -- Open the exported file
    vim.cmd('edit ' .. vim.fn.fnameescape(temp_file))
    vim.notify('Exported registry key to: ' .. temp_file, vim.log.levels.INFO)
  end))
end
