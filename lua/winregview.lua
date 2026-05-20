local M = {}

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

--- Parse winreg:///key/{path} URIs
--- @param uri string
--- @return string path
local function parse_key_uri(uri)
  local prefix = 'winreg:///key/'
  if not vim.startswith(uri, prefix) then
    return uri
  end
  return uri:sub(#prefix + 1)
end

--- Parse winreg:///value/{path}#value={name} URIs
--- @param uri string
--- @return string path, string|nil value_name
local function parse_value_uri(uri)
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
local function normalize_reg_path(path)
  if not path or path == '' then
    return nil
  end
  
  -- Convert forward slashes to backslashes
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
  
  -- Convert to backslash
  path = path:gsub('/', '\\')
  
  -- Find last backslash
  local parent = path:match('^(.+)\\[^\\]+$')
  return parent
end

--- Toggle between WOW6432Node (32-bit) and normal (64-bit) registry path
--- @param path string Registry path
--- @return string|nil toggled path or nil if not applicable
local function toggle_wow6432node(path)
  if not path or path == '' then
    return nil
  end
  
  -- Convert to backslash for consistency
  path = path:gsub('/', '\\')
  
  -- Check if path contains WOW6432Node
  if path:match('\\WOW6432Node\\') then
    -- Remove WOW6432Node
    return path:gsub('\\WOW6432Node\\', '\\')
  else
    -- Check if we can add WOW6432Node (must be in a location where it makes sense)
    -- WOW6432Node typically appears in: HKCR, HKLM\Software, HKLM\System
    -- Use case-insensitive matching with :lower()
    local lower_path = path:lower()
    
    -- Try to insert WOW6432Node after appropriate prefixes
    if lower_path:match('^hkey_classes_root\\') then
      -- Insert after HKCR
      return path:gsub('^(HKEY_CLASSES_ROOT)\\', '%1\\WOW6432Node\\', 1)
    elseif lower_path:match('^hkey_local_machine\\software\\') then
      -- Insert after HKLM\Software (case-insensitive replacement)
      local prefix_end = path:lower():find('\\software\\')
      if prefix_end then
        local prefix = path:sub(1, prefix_end + 8)  -- Include "\Software"
        local suffix = path:sub(prefix_end + 9)      -- Everything after "\Software\"
        return prefix .. '\\WOW6432Node' .. suffix
      end
    elseif lower_path:match('^hkey_local_machine\\system\\currentcontrolset\\services\\') then
      -- Insert after Services
      local services_end = path:lower():find('\\services\\')
      if services_end then
        local prefix = path:sub(1, services_end + 9)  -- Include "\Services"
        local suffix = path:sub(services_end + 10)     -- Everything after "\Services\"
        return prefix .. '\\WOW6432Node' .. suffix
      end
    end
    
    -- If no pattern matched, return nil (not applicable)
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
  
  local current_key = nil
  
  for _, line in ipairs(lines) do
    -- Remove carriage returns
    line = line:gsub('\r', '')
    
    -- Skip empty lines
    if line:match('^%s*$') then
      goto continue
    end
    
    -- Check if this is a subkey line (starts with HKEY)
    if vim.startswith(line, 'HKEY') then
      current_key = line
      
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
        
        -- Handle (Default) value
        if value_name == '(Default)' then
          value_name = '(Default)'
        end
        
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

-- View a registry key (list subkeys and values)
function M.bufread_key(args)
  local buf = args.buf
  local uri = args.file
  local reg_path = parse_key_uri(uri)
  local bufOpt = { buf = buf }
  
  vim.api.nvim_set_option_value('modifiable', true, bufOpt)
  vim.api.nvim_set_option_value('buftype', 'nofile', bufOpt)
  vim.api.nvim_set_option_value('swapfile', false, bufOpt)
  vim.api.nvim_set_option_value('filetype', 'winregview', bufOpt)
  vim.api.nvim_set_option_value('bufhidden', 'hide', bufOpt)
  vim.api.nvim_set_option_value('buflisted', false, bufOpt)
  
  -- Special case: empty path = show root keys
  if reg_path == '' then
    local lines = { '# Windows Registry Root Keys', '' }
    
    for _, root in ipairs(ROOT_KEYS) do
      table.insert(lines, '[KEY]  ' .. root.full .. '\\')
    end
    
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value('modifiable', false, bufOpt)
    
    -- Set up Enter key to navigate
    vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>', '', {
      noremap = true,
      silent = true,
      callback = function()
        local row = unpack(vim.api.nvim_win_get_cursor(0))
        local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
        if not line or line == '' or vim.startswith(line, '#') then
          return
        end
        
        -- Extract root key name
        local key_name = line:match('%[KEY%]%s+(.+)\\')
        if key_name then
          local target_uri = 'winreg:///key/' .. key_name
          vim.cmd('edit ' .. vim.fn.fnameescape(target_uri))
        end
      end,
    })
    
    vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':bd!<CR>', { noremap = true, silent = true })
    return
  end
  
  -- Normalize the path
  local normalized_path = normalize_reg_path(reg_path)
  if not normalized_path then
    vim.notify('Invalid registry path: ' .. reg_path, vim.log.levels.ERROR)
    vim.api.nvim_set_option_value('modifiable', false, bufOpt)
    return
  end
  
  -- Query registry asynchronously
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
    
    -- Parse output
    local entries = parse_reg_output(result.stdout or '', normalized_path)
    
    -- Separate keys and values
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
    
    -- Map from line number to entry
    local line_to_entry = {}
    
    -- Add parent navigation hint
    local parent = get_parent_path(normalized_path)
    if parent then
      table.insert(lines, '.. (parent: ' .. parent .. ')')
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
    vim.b[buf].winreg_entries = entries
    vim.b[buf].winreg_path = normalized_path
    vim.b[buf].winreg_line_to_entry = line_to_entry
    
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
    end, bufOpt)
    
    -- Set up W key to toggle WOW6432Node
    vim.keymap.set('n', 'W', function()
      local toggled_path = toggle_wow6432node(normalized_path)
      if toggled_path then
        local target_uri = 'winreg:///key/' .. toggled_path
        vim.cmd('edit ' .. vim.fn.fnameescape(target_uri))
      else
        vim.notify('WOW6432Node toggle not applicable for this path', vim.log.levels.INFO)
      end
    end, bufOpt)
    
    vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':bd!<CR>', { noremap = true, silent = true })
  end))
end

-- View a specific registry value
function M.bufread_value(args)
  local buf = args.buf
  local uri = args.file
  local reg_path, value_name = parse_value_uri(uri)
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
  
  local normalized_path = normalize_reg_path(reg_path)
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
    
    -- Set up - key to go back to parent key
    vim.keymap.set('n', '-', function()
      local target_uri = 'winreg:///key/' .. normalized_path
      vim.cmd('edit ' .. vim.fn.fnameescape(target_uri))
    end, bufOpt)
    
    -- Set up W key to toggle WOW6432Node
    vim.keymap.set('n', 'W', function()
      local toggled_path = toggle_wow6432node(normalized_path)
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
    end, bufOpt)
    
    vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':bd!<CR>', { noremap = true, silent = true })
  end))
end

return M
