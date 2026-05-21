local M = {}

--- finds the first occurrence of 'to_find' in 'input'
---@param input string
---@param to_find string
---@param case_insensitive boolean
---@param start_index number? if set only starts searching from that location in the input string onwards
---@return number|nil match_start starting position of the match (1-indexed), or nil if not found
---@return number|nil match_end ending position of the match (1-indexed), or nil if not found
function M.string_find(input, to_find, case_insensitive, start_index)
  if not input or not to_find then
    return nil, nil
  end

  -- Handle empty string to find
  if to_find == '' then
    return nil, nil
  end

  -- Set default start_index to 1
  start_index = start_index or 1

  -- Validate start_index
  if start_index < 1 or start_index > #input then
    return nil, nil
  end

  if case_insensitive then
    -- Case-insensitive search: find in lowercase versions
    local lower_input = input:lower()
    local lower_to_find = to_find:lower()

    local match_start, match_end = lower_input:find(lower_to_find, start_index, true)
    return match_start, match_end
  else
    -- Case-sensitive search: find with plain text search
    local match_start, match_end = input:find(to_find, start_index, true)
    return match_start, match_end
  end
end

--- replaces all occurnces of 'to_replace' in 'input' with 'replacement'
---@param input string
---@param to_replace string
---@param replacement string
---@param case_insensitive boolean
---@param start_index number? if set only starts replacing from that location in the input string onwards
function M.string_replace(input, to_replace, replacement, case_insensitive, start_index)
  if not input or not to_replace or not replacement then
    return input
  end

  -- Handle empty string to replace
  if to_replace == '' then
    return input
  end

  -- Set default start_index to 1
  start_index = start_index or 1

  -- Validate start_index
  if start_index < 1 or start_index > #input then
    return input
  end

  -- Extract the part before start_index (unchanged) and the part to process
  local prefix = input:sub(1, start_index - 1)
  local to_process = input:sub(start_index)

  -- Perform replacement based on case sensitivity
  local result = ''
  local pos = 1

  if case_insensitive then
    -- Case-insensitive replacement: find matches in lowercase version
    local lower_to_process = to_process:lower()
    local lower_to_replace = to_replace:lower()

    while pos <= #to_process do
      local match_start, match_end = lower_to_process:find(lower_to_replace, pos, true)
      if match_start then
        -- Append everything before the match
        result = result .. to_process:sub(pos, match_start - 1)
        -- Append the replacement
        result = result .. replacement
        -- Move position past the match
        pos = match_end + 1
      else
        -- No more matches, append the rest
        result = result .. to_process:sub(pos)
        break
      end
    end
  else
    -- Case-sensitive replacement: find matches with plain text search
    while pos <= #to_process do
      local match_start, match_end = to_process:find(to_replace, pos, true)
      if match_start then
        -- Append everything before the match
        result = result .. to_process:sub(pos, match_start - 1)
        -- Append the replacement
        result = result .. replacement
        -- Move position past the match
        pos = match_end + 1
      else
        -- No more matches, append the rest
        result = result .. to_process:sub(pos)
        break
      end
    end
  end

  return prefix .. result
end

return M
