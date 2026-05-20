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
  end
  
  local uri = "winreg:///key/" .. reg_path
  vim.cmd("edit " .. vim.fn.fnameescape(uri))
end, {
  nargs = "*",
  desc = "Open Windows Registry view",
  complete = function(ArgLead, CmdLine, CursorPos)
    -- Basic completion for root keys
    local root_keys = {
      'HKEY_CLASSES_ROOT',
      'HKEY_CURRENT_USER',
      'HKEY_LOCAL_MACHINE',
      'HKEY_USERS',
      'HKEY_CURRENT_CONFIG',
      'HKCR',
      'HKCU',
      'HKLM',
      'HKU',
      'HKCC',
    }
    
    local matches = {}
    for _, key in ipairs(root_keys) do
      if key:lower():find(ArgLead:lower(), 1, true) then
        table.insert(matches, key)
      end
    end
    
    return matches
  end,
})
