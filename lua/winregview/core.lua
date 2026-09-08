local M = {}


---@class winreg.bufinfo_key
---@field type 'key'
---@field uri string
---@field entries table
---@field path string
---@field line_to_entry table<number, string>

---@class winreg.bufinfo_value
---@field type 'value'
---@field uri string
---@field entries table
---@field path string
---@field value_name string

---@alias winreg.bufinfo winreg.bufinfo_key | winreg.bufinfo_value

-- Registry root keys mapping
local ROOT_KEYS = {
  { full = "HKEY_CLASSES_ROOT", abbr = "HKCR" },
  { full = "HKEY_CURRENT_USER", abbr = "HKCU" },
  { full = "HKEY_LOCAL_MACHINE", abbr = "HKLM" },
  { full = "HKEY_USERS", abbr = "HKU" },
  { full = "HKEY_CURRENT_CONFIG", abbr = "HKCC" },
}

-- Registry value type names from reg.exe output
local REG_TYPES = {
  REG_SZ = "String",
  REG_EXPAND_SZ = "ExpandString",
  REG_BINARY = "Binary",
  REG_DWORD = "DWord",
  REG_QWORD = "QWord",
  REG_MULTI_SZ = "MultiString",
  REG_NONE = "None",
}

local is_admin

local function is_running_as_admin()
  if is_admin ~= nil then
    return is_admin
  end

  local result = vim.system({
    'powershell.exe',
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    '[bool](([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))',
  }, { text = true }):wait()

  is_admin = result.code == 0 and vim.trim(result.stdout or '') == 'True'
  return is_admin
end

function M.parse_uri_both(uri)
  local prefix = 'winreg:///key/'
  if vim.startswith(uri, prefix) then
    return M.parse_key_uri(uri)
  else
    return M.parse_value_uri(uri)
  end
end

--- Parse winreg:///key/{path} URIs
--- @param uri string
--- @return string path
function M.parse_key_uri(uri)
  local prefix = 'winreg:///key/'
  if not vim.startswith(uri, prefix) then
    return uri
  end
  return uri:sub(#prefix + 1)
end

--- Parse winreg:///value/{path}#value={name} URIs
--- @param uri string
--- @return string path, string|nil value_name
function M.parse_value_uri(uri)
  local prefix = 'winreg:///value/'
  if not vim.startswith(uri, prefix) then
    return uri, nil
  end

  local body, frag = uri:match('^([^#]+)#?(.*)$')
  local path = body:sub(#prefix + 1)

  if not frag or frag == '' then
    return path, nil
  end

  local value_name = frag:match('[&?#]?value=(.*)$')
  if not value_name or value_name == '' then
    return path, nil
  end

  -- URL decode
  value_name = value_name:gsub('+', ' ')
  value_name = value_name:gsub('%%(%x%x)', function(hex)
    return string.char(tonumber(hex, 16))
  end)

  return path, value_name
end

--- Normalize registry path for reg.exe
--- @param path string
--- @return string|nil normalized path or nil if invalid
function M.normalize_reg_path(path)
  if not path or path == '' then
    return nil
  end

  path = path:gsub('/', '\\')

  -- Expand abbreviations
  for _, root in ipairs(ROOT_KEYS) do
    if vim.startswith(path, root.abbr) then
      path = path:gsub('^' .. root.abbr, root.full)
      break
    end
  end

  return path
end

--- Get parent registry path
--- @param path string
--- @return string|nil parent path
local function get_parent_path(path)
  if not path or path == '' then
    return nil
  end

  path = path:gsub('/', '\\')

  -- Find last backslash
  local parent = path:match('^(.+)\\[^\\]+$')
  return parent
end


--- Toggle between WOW6432Node (32-bit) and normal (64-bit) registry path
--- @param path string Registry path
--- @return string|nil toggled path or nil if not applicable
function M.toggle_wow6432node(path)
  if not path or path == '' then
    return nil
  end

  local str_util = require('winregview.str_utils')

  path = path:gsub('/', '\\')

  -- Check if path contains WOW6432Node
  if str_util.string_find(path, '\\WOW6432Node\\', true) then

    return str_util.string_replace(path, '\\WOW6432Node\\', '\\', true)
  else

    local wow6432node_redirected_keys = {
      -- HKEY_LOCAL_MACHINE redirected keys
      "HKEY_LOCAL_MACHINE\\SOFTWARE",
      "HKEY_LOCAL_MACHINE\\SOFTWARE\\Classes\\CLSID",
      "HKEY_LOCAL_MACHINE\\SOFTWARE\\Classes\\DirectShow",
      "HKEY_LOCAL_MACHINE\\SOFTWARE\\Classes\\Interface",
      "HKEY_LOCAL_MACHINE\\SOFTWARE\\Classes\\Media Type",
      "HKEY_LOCAL_MACHINE\\SOFTWARE\\Classes\\MediaFoundation",

      -- HKEY_CURRENT_USER redirected keys
      "HKEY_CURRENT_USER\\SOFTWARE\\Classes\\CLSID",
      "HKEY_CURRENT_USER\\SOFTWARE\\Classes\\DirectShow",
      "HKEY_CURRENT_USER\\SOFTWARE\\Classes\\Interface",
      "HKEY_CURRENT_USER\\SOFTWARE\\Classes\\Media Type",
      "HKEY_CURRENT_USER\\SOFTWARE\\Classes\\MediaFoundation",
    }

    for _, value in ipairs(wow6432node_redirected_keys) do

      -- Try to replace the prefix with the same prefix + \WOW6432Node
      -- Using case-insensitive matching
      local result = str_util.string_replace(path, value, value .. '\\WOW6432Node', true)

      -- If replacement occurred (result differs from original path), return it
      if result ~= path then
        return result
      end
    end

    return nil
  end
end

--- Parse reg.exe query output into subkeys and values
--- @param output string Output from reg.exe query
--- @param current_path string|nil The current registry path being queried (to filter it out from subkeys)
--- @return table entries List of {type="key"|"value", name=..., reg_type=..., data=...}
local function parse_reg_output(output, current_path)
  local entries = {}
  local lines = vim.split(output, '\n', { plain = true })

  for _, line in ipairs(lines) do
    -- Remove carriage returns
    line = line:gsub('\r', '')

    -- Skip empty lines
    if line:match('^%s*$') then
      goto continue
    end

    -- Check if this is a subkey line (starts with HKEY)
    if vim.startswith(line, 'HKEY') then

      -- Skip if this is the current path itself (not a subkey)
      if current_path and line == current_path then
        goto continue
      end

      -- Extract just the subkey name (last component)
      local subkey_name = line:match('\\([^\\]+)$')
      if subkey_name then
        table.insert(entries, {
          type = 'key',
          name = subkey_name,
          full_path = line,
        })
      end
      goto continue
    end

    -- Check if this is a value line (has 4 spaces at start, or starts with REG_)
    -- Format: "    ValueName    REG_TYPE    Data"
    local value_match = line:match('^%s+(.+)$')
    if value_match then
      -- Split by multiple spaces/tabs
      local parts = {}
      for part in value_match:gmatch('%S+') do
        table.insert(parts, part)
      end

      if #parts >= 2 then
        local value_name = parts[1]
        local reg_type = parts[2]
        local data = table.concat(parts, ' ', 3) or ''

        table.insert(entries, {
          type = 'value',
          name = value_name,
          reg_type = reg_type,
          data = data,
        })
      end
    end

    ::continue::
  end

  return entries
end

--- Format registry entry for display
--- @param entry table Entry from parse_reg_output
--- @return string formatted line
local function format_entry(entry)
  if entry.type == 'key' then
    return '[KEY]  ' .. entry.name .. '\\'
  else
    local type_str = REG_TYPES[entry.reg_type] or entry.reg_type
    local data_str = entry.data

    -- Truncate long data
    if #data_str > 60 then
      data_str = data_str:sub(1, 60) .. '...'
    end

    return string.format('[%-12s]  %-30s  %s', type_str, entry.name, data_str)
  end
end

local function register_toggle_buf(buf)
  local function impl()
    require('winregview.favorites').toggle_buf()
  end
  vim.keymap.set('n', '<leader>wf', impl, { buffer = buf })
end

local function edit_value_data(buf, uri, path, value_name, reg_type, current_data)
  local prompt = string.format('New data for %s (%s): ', value_name, reg_type)

  vim.ui.input({
    prompt = prompt,
    default = current_data,
  }, function(input)
    if input == nil then
      return
    end

    local cmd = { 'reg.exe', 'add', path }
    if not is_running_as_admin() then
      cmd = { 'sudo', 'reg.exe', 'add', path }
    end

    if value_name == '(Default)' then
      vim.list_extend(cmd, { '/ve' })
    else
      vim.list_extend(cmd, { '/v', value_name })
    end

    vim.list_extend(cmd, { '/t', reg_type, '/d', input, '/f', })

    vim.system(cmd, { text = true }, vim.schedule_wrap(function(result)
      if result.code ~= 0 then
        local err_msg = result.stderr or 'Failed to update registry value'
        vim.notify('reg.exe add failed: ' .. err_msg, vim.log.levels.ERROR)
        return
      end

      vim.notify('Updated registry value: ' .. value_name, vim.log.levels.INFO)

      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_call(buf, function()
          vim.cmd('edit! ' .. vim.fn.fnameescape(uri))
        end)
      end
    end))
  end)
end

-- View a registry key (list subkeys and values)
function M.bufread_key(args)
  local buf = args.buf
  local uri = args.file
  local reg_path = M.parse_key_uri(uri)
  local bufOpt = { buf = buf }

  vim.api.nvim_set_option_value('bufhidden', 'hide', bufOpt)
  vim.api.nvim_set_option_value('buflisted', false, bufOpt)
  vim.api.nvim_set_option_value('buftype', 'nofile', bufOpt)
  vim.api.nvim_set_option_value('filetype', 'winregview', bufOpt)
  vim.api.nvim_set_option_value('swapfile', false, bufOpt)

  vim.api.nvim_set_option_value('modifiable', true, bufOpt)

  -- Special case: empty path = show root keys
  if reg_path == '' then
    local lines = { '# Windows Registry Root Keys', '' }

    for _, root in ipairs(ROOT_KEYS) do
      table.insert(lines, '[KEY]  ' .. root.full .. '\\')
    end

    local favs = require('winregview.favorites')
    if #favs.entries > 0 then
      table.insert(lines, '')
      table.insert(lines, '# Favorites')
      for _, fav_uri in ipairs(favs.entries) do

        local fav_key, fav_value = M.parse_uri_both(fav_uri)
        if not fav_value then
          table.insert(lines, '[KEY]  ' .. fav_key .. '\\')
        else
          table.insert(lines, '[VALUE]  ' .. fav_key .. '#value=' .. fav_value)
        end
      end
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value('modifiable', false, bufOpt)

    vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>', '', {
      noremap = true,
      silent = true,
      callback = function()
        local row = unpack(vim.api.nvim_win_get_cursor(0))
        local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
        if not line or line == '' or vim.startswith(line, '#') then
          return
        end

        local path = line:match('%[KEY%]%s+(.+)\\')
        if path then
          local target_uri = 'winreg:///key/' .. path
          vim.cmd('edit ' .. vim.fn.fnameescape(target_uri))
        end

        path = line:match('%[VALUE%]%s+(.+)')
        if path then
          local target_uri = 'winreg:///value/' .. path
          vim.cmd('edit ' .. vim.fn.fnameescape(target_uri))
        end
      end,
    })

    vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':bd!<CR>', { noremap = true, silent = true })

    vim.api.nvim_buf_call(buf, function()
      ---@diagnostic disable-next-line: param-type-mismatch
      pcall(vim.cmd, '/[')
      vim.cmd.nohlsearch()
    end)
    return
  end

  local normalized_path = M.normalize_reg_path(reg_path)
  if not normalized_path then
    vim.notify('Invalid registry path: ' .. reg_path, vim.log.levels.ERROR)
    vim.api.nvim_set_option_value('modifiable', false, bufOpt)
    return
  end

  vim.system({ 'reg.exe', 'query', normalized_path }, { text = true }, vim.schedule_wrap(function(result)
    if result.code ~= 0 then
      local err_msg = result.stderr or 'Failed to query registry'
      vim.notify('reg.exe failed: ' .. err_msg, vim.log.levels.ERROR)
      local lines = {
        '# Error querying registry',
        '',
        'Path: ' .. normalized_path,
        '',
        'Error:',
      }
      -- Split error message into lines to avoid newline issues
      local err_lines = vim.split(err_msg, '\n', { plain = true })
      for _, line in ipairs(err_lines) do
        table.insert(lines, line)
      end
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.api.nvim_set_option_value('modifiable', false, bufOpt)
      return
    end

    local entries = parse_reg_output(result.stdout or '', normalized_path)

    local keys = {}
    local values = {}
    for _, entry in ipairs(entries) do
      if entry.type == 'key' then
        table.insert(keys, entry)
      else
        table.insert(values, entry)
      end
    end

    -- Build display lines and track which line corresponds to which entry
    local lines = {
      '# Registry Key: ' .. normalized_path,
      '',
    }

    local line_to_entry = {}
    local parent = get_parent_path(normalized_path)
    if parent then
      table.insert(lines, '.. (go to parent key)')
      table.insert(lines, '')
    end

    -- Add subkeys
    if #keys > 0 then
      table.insert(lines, '## Subkeys (' .. #keys .. ')')
      table.insert(lines, '')
      for _, entry in ipairs(keys) do
        local line_num = #lines + 1
        table.insert(lines, format_entry(entry))
        line_to_entry[line_num] = entry
      end
      table.insert(lines, '')
    end

    -- Add values
    if #values > 0 then
      table.insert(lines, '## Values (' .. #values .. ')')
      table.insert(lines, '')
      for _, entry in ipairs(values) do
        local line_num = #lines + 1
        table.insert(lines, format_entry(entry))
        line_to_entry[line_num] = entry
      end
    end

    if #keys == 0 and #values == 0 then
      table.insert(lines, '(No subkeys or values)')
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value('modifiable', false, bufOpt)

    -- Store entries and line mapping in buffer variable for navigation
    ---@type winreg.bufinfo_key
    vim.b[buf].winreg = {
      type = 'key',
      entries = entries,
      path = normalized_path,
      line_to_entry = line_to_entry,
      uri = uri,
    }

    register_toggle_buf(buf)

    -- Set up Enter key to navigate to subkeys or view values
    vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>', '', {
      noremap = true,
      silent = true,
      callback = function()
        local row = unpack(vim.api.nvim_win_get_cursor(0))
        local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
        if not line or line == '' or vim.startswith(line, '#') then
          return
        end

        -- Handle parent navigation
        if vim.startswith(line, '..') then
          if parent then
            local target_uri = 'winreg:///key/' .. parent
            vim.cmd('edit ' .. vim.fn.fnameescape(target_uri))
          end
          return
        end

        -- Use line-to-entry mapping to get the actual entry
        local entry = line_to_entry[row]
        if not entry then
          return
        end

        if entry.type == 'key' then
          -- Navigate to subkey
          local target_uri = 'winreg:///key/' .. normalized_path .. '\\' .. entry.name
          vim.cmd('edit ' .. vim.fn.fnameescape(target_uri))
        elseif entry.type == 'value' then
          -- URL encode the value name
          local encoded = entry.name:gsub('([^%w%-%.%_%~])', function(c)
            return string.format('%%%02X', string.byte(c))
          end)

          local target_uri = 'winreg:///value/' .. normalized_path .. '#value=' .. encoded
          vim.cmd('edit ' .. vim.fn.fnameescape(target_uri))
        end
      end,
    })

    -- Set up - key to go to parent
    vim.keymap.set('n', '-', function()
      if parent then
        local target_uri = 'winreg:///key/' .. parent
        vim.cmd('edit ' .. vim.fn.fnameescape(target_uri))
      else
        -- Go to root
        vim.cmd('edit winreg:///key/')
      end
    end, { buffer = buf })

    -- Set up W key to toggle WOW6432Node
    vim.keymap.set('n', 'W', function()
      local toggled_path = M.toggle_wow6432node(normalized_path)
      if toggled_path then
        local target_uri = 'winreg:///key/' .. toggled_path
        vim.cmd('edit ' .. vim.fn.fnameescape(target_uri))
      else
        vim.notify('WOW6432Node toggle not applicable for this path', vim.log.levels.INFO)
      end
    end, { buffer = buf })

    vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':bd!<CR>', { noremap = true, silent = true })

    vim.api.nvim_buf_call(buf, function()
      ---@diagnostic disable-next-line: param-type-mismatch
      pcall(vim.cmd, '/\\[')
      vim.cmd.nohlsearch()
    end)
  end))

end

-- View a specific registry value
function M.bufread_value(args)
  local buf = args.buf
  local uri = args.file
  local reg_path, value_name = M.parse_value_uri(uri)
  local bufOpt = { buf = buf }

  vim.api.nvim_set_option_value('modifiable', true, bufOpt)
  vim.api.nvim_set_option_value('buftype', 'nofile', bufOpt)
  vim.api.nvim_set_option_value('swapfile', false, bufOpt)
  vim.api.nvim_set_option_value('filetype', 'winregvalue', bufOpt)
  vim.api.nvim_set_option_value('bufhidden', 'hide', bufOpt)
  vim.api.nvim_set_option_value('buflisted', false, bufOpt)

  if not value_name then
    vim.notify('No value name specified', vim.log.levels.ERROR)
    vim.api.nvim_set_option_value('modifiable', false, bufOpt)
    return
  end

  local normalized_path = M.normalize_reg_path(reg_path)
  if not normalized_path then
    vim.notify('Invalid registry path: ' .. reg_path, vim.log.levels.ERROR)
    vim.api.nvim_set_option_value('modifiable', false, bufOpt)
    return
  end

  -- Query the specific value
  -- For default value, use /ve instead of /v (Default)
  local cmd
  if value_name == '(Default)' then
    cmd = { 'reg.exe', 'query', normalized_path, '/ve' }
  else
    cmd = { 'reg.exe', 'query', normalized_path, '/v', value_name }
  end

  vim.system(cmd, { text = true }, vim.schedule_wrap(function(result)
    if result.code ~= 0 then
      local err_msg = result.stderr or 'Failed to query registry value'
      vim.notify('reg.exe failed: ' .. err_msg, vim.log.levels.ERROR)
      local lines = {
        '# Error querying registry value',
        '',
        'Path: ' .. normalized_path,
        'Value: ' .. value_name,
        '',
        'Error:',
      }
      -- Split error message into lines to avoid newline issues
      local err_lines = vim.split(err_msg, '\n', { plain = true })
      for _, line in ipairs(err_lines) do
        table.insert(lines, line)
      end
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.api.nvim_set_option_value('modifiable', false, bufOpt)
      return
    end

    -- Parse the value
    local entries = parse_reg_output(result.stdout or '', normalized_path)
    local value_entry = nil

    for _, entry in ipairs(entries) do
      if entry.type == 'value' and entry.name == value_name then
        value_entry = entry
        break
      end
    end

    if not value_entry then
      vim.notify('Value not found: ' .. value_name, vim.log.levels.ERROR)
      vim.api.nvim_set_option_value('modifiable', false, bufOpt)
      return
    end

    -- Build display
    local type_str = REG_TYPES[value_entry.reg_type] or value_entry.reg_type
    local lines = {
      '# Registry Value',
      '',
      'Path:  ' .. normalized_path,
      'Name:  ' .. value_entry.name,
      'Type:  ' .. type_str .. ' (' .. value_entry.reg_type .. ')',
      '',
      '## Data',
      '',
    }

    -- Split data into lines for better readability
    local data_lines = vim.split(value_entry.data, '\n', { plain = true })
    vim.list_extend(lines, data_lines)

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value('modifiable', false, bufOpt)

    ---@type winreg.bufinfo_value
    vim.b[buf].winreg = {
      type = 'value',
      entries = entries,
      path = normalized_path,
      value_name = value_name,
      uri = uri,
    }

    -- Set up - key to go back to parent key
    vim.keymap.set('n', '-', function()
      local target_uri = 'winreg:///key/' .. normalized_path
      vim.cmd('edit ' .. vim.fn.fnameescape(target_uri))
    end, { buffer = buf })

    register_toggle_buf(buf)

    -- Set up W key to toggle WOW6432Node
    vim.keymap.set('n', 'W', function()
      local toggled_path = M.toggle_wow6432node(normalized_path)
      if toggled_path then
        -- URL encode the value name for the new path
        local encoded = value_name:gsub('([^%w%-%.%_%~])', function(c)
          return string.format('%%%02X', string.byte(c))
        end)
        local target_uri = 'winreg:///value/' .. toggled_path .. '#value=' .. encoded
        vim.cmd('edit ' .. vim.fn.fnameescape(target_uri))
      else
        vim.notify('WOW6432Node toggle not applicable for this path', vim.log.levels.INFO)
      end
    end, { buffer = buf })

    vim.keymap.set('n', 'E', function()
      edit_value_data(buf, uri, normalized_path, value_entry.name, value_entry.reg_type, value_entry.data)
    end, { buffer = buf })

    vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':bd!<CR>', { noremap = true, silent = true })
  end))
end

--- Complete registry paths
--- @param start string The partial path typed so far
--- @return table List of completion candidates
function M.registry_path_complete(start)
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

return M
