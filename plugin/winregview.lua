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

--- Complete registry paths
--- @param start string The partial path typed so far
--- @return table List of completion candidates
local function registry_path_complete(start)
  -- Root keys for completion
  local root_keys = {
    'HKEY_CLASSES_ROOT',
    'HKEY_CURRENT_USER',
    'HKEY_LOCAL_MACHINE',
    'HKEY_USERS',
    'HKEY_CURRENT_CONFIG',
  }

  -- If empty or just starting, return root keys
  if start == '' then
    return root_keys
  end

  -- Remove any escaped backslashes from previous completion
  start = start:gsub([[\\]], [[\]])

  -- Normalize separators to backslash
  start = start:gsub('/', '\\')

  local parent_path, filter

  -- Check if path ends with backslash (user wants to see subkeys)
  if start:sub(#start) == '\\' then
    parent_path = start:sub(1, #start - 1)  -- Remove trailing backslash
    filter = nil
  else
    -- Extract parent path and filter
    local last_sep = start:match('.*()\\')
    if last_sep then
      parent_path = start:sub(1, last_sep - 1)
      filter = start:sub(last_sep + 1)
    else
      -- No separator yet, completing root key
      parent_path = nil
      filter = start
    end
  end

  local entries = {}

  -- If no parent path, complete root keys
  if not parent_path then
    for _, key in ipairs(root_keys) do
      table.insert(entries, key .. '\\')
    end
  else
    -- Query registry for subkeys
    local result = vim.system({ 'reg.exe', 'query', parent_path }, { text = true }):wait()

    if result.code == 0 then
      local lines = vim.split(result.stdout or '', '\n', { plain = true })

      for _, line in ipairs(lines) do
        line = line:gsub('\r', '')

        -- Check if this is a subkey line (starts with HKEY)
        if vim.startswith(line, 'HKEY') then
          -- Skip the parent path itself
          if line ~= parent_path then
            -- Extract just the subkey name (last component)
            local subkey_name = line:match('\\([^\\]+)$')
            if subkey_name then
              table.insert(entries, parent_path .. '\\' .. subkey_name .. '\\')
            end
          end
        end
      end
    end
  end

  -- Filter entries based on what's been typed (case-insensitive)
  if filter and filter ~= '' then
    local lower_filter = filter:lower()
    local filtered = {}
    for _, entry in ipairs(entries) do
      -- For root keys: match the entire key name before the backslash
      -- For subkeys: extract the last component
      local component_to_match
      if not entry:match('\\.*\\') then
        -- Root key case: HKEY_CURRENT_USER\
        component_to_match = entry:match('^(.+)\\$')
      else
        -- Subkey case: HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\
        component_to_match = entry:match('\\([^\\]+)\\$')
      end

      if component_to_match and component_to_match:lower():find(lower_filter, 1, true) == 1 then
        table.insert(filtered, entry)
      end
    end
    entries = filtered
  end

  -- Escape spaces for command line
  local escaped_entries = {}
  for _, entry in ipairs(entries) do
    local escaped = entry:gsub(' ', [[\ ]])
    table.insert(escaped_entries, escaped)
  end

  -- Sort entries alphabetically (case-insensitive)
  table.sort(escaped_entries, function(a, b)
    return a:lower() < b:lower()
  end)

  return escaped_entries
end

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
  complete = function(ArgLead, CmdLine, CursorPos)
    return registry_path_complete(ArgLead)
  end,
})
