local regview = require('winregview')
local function assert_eq(value, expected)

  if value ~= expected then
    error('Expected ' .. (expected or '<nil>') .. ', got '  .. (value or '<nil>'))
  end
end

-- local value = regview.toggle_wow6432node([[HKEY_LOCAL_MACHINE\SOFTWARE\DATAflor]])
-- assert_eq(value, [[HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\DATAflor]])

-- Tests for string_replace function

local str = require('winregview.str_utils')


print("Running string_replace tests...")

-- Test 1: Basic case-sensitive replacement
local result1 = str.string_replace("hello world hello", "hello", "goodbye", false)
assert_eq(result1, "goodbye world goodbye")
print("✓ Test 1: Basic case-sensitive replacement")

-- Test 2: Case-insensitive replacement
local result2 = str.string_replace("Hello World HELLO", "hello", "goodbye", true)
assert_eq(result2, "goodbye World goodbye")
print("✓ Test 2: Case-insensitive replacement")

-- Test 3: Case-sensitive (should not replace different case)
local result3 = str.string_replace("Hello World HELLO", "hello", "goodbye", false)
assert_eq(result3, "Hello World HELLO")
print("✓ Test 3: Case-sensitive no match")

-- Test 4: Replacement with start_index
local result4 = str.string_replace("hello world hello", "hello", "goodbye", false, 7)
assert_eq(result4, "hello world goodbye")
print("✓ Test 4: Replacement with start_index")

-- Test 5: Replacement with start_index case-insensitive
local result5 = str.string_replace("Hello World HELLO", "hello", "goodbye", true, 7)
assert_eq(result5, "Hello World goodbye")
print("✓ Test 5: Replacement with start_index (case-insensitive)")

-- Test 6: Empty string to replace
local result6 = str.string_replace("hello world", "", "goodbye", false)
assert_eq(result6, "hello world")
print("✓ Test 6: Empty string to replace")

-- Test 7: No match found
local result7 = str.string_replace("hello world", "foo", "bar", false)
assert_eq(result7, "hello world")
print("✓ Test 7: No match found")

-- Test 8: Replace with special characters
local result8 = str.string_replace("file.txt.bak", ".txt", ".md", false)
assert_eq(result8, "file.md.bak")
print("✓ Test 8: Special characters in pattern")

-- Test 9: Replace with regex special characters
local result9 = str.string_replace("test(1) and test(2)", "(1)", "(ONE)", false)
assert_eq(result9, "test(ONE) and test(2)")
print("✓ Test 9: Regex special characters")

-- Test 10: Replace with percent sign
local result10 = str.string_replace("50% off 100%", "%", " percent", false)
assert_eq(result10, "50 percent off 100 percent")
print("✓ Test 10: Percent sign in replacement")

-- Test 11: Nil input
local result11 = str.string_replace(nil, "hello", "goodbye", false)
assert_eq(result11, nil)
print("✓ Test 11: Nil input")

-- Test 12: Nil to_replace
local result12 = str.string_replace("hello", nil, "goodbye", false)
assert_eq(result12, "hello")
print("✓ Test 12: Nil to_replace")

-- Test 13: Nil replacement
local result13 = str.string_replace("hello", "hello", nil, false)
assert_eq(result13, "hello")
print("✓ Test 13: Nil replacement")

-- Test 14: start_index out of bounds (too large)
local result14 = str.string_replace("hello", "hello", "goodbye", false, 100)
assert_eq(result14, "hello")
print("✓ Test 14: start_index out of bounds")

-- Test 15: start_index = 1 (default behavior)
local result15 = str.string_replace("hello world", "hello", "goodbye", false, 1)
assert_eq(result15, "goodbye world")
print("✓ Test 15: start_index = 1")

-- Test 16: start_index at exact match position
local result16 = str.string_replace("hello world hello", "hello", "goodbye", false, 13)
assert_eq(result16, "hello world goodbye")
print("✓ Test 16: start_index at exact match position")

-- Test 17: Multiple occurrences with overlapping pattern
local result17 = str.string_replace("aaaa", "aa", "b", false)
assert_eq(result17, "bb")
print("✓ Test 17: Overlapping pattern replacement")

-- Test 18: Empty string input
local result18 = str.string_replace("", "hello", "goodbye", false)
assert_eq(result18, "")
print("✓ Test 18: Empty string input")

-- Test 19: Replacement that creates the search pattern
local result19 = str.string_replace("abc", "a", "aa", false)
assert_eq(result19, "aabc")
print("✓ Test 19: Replacement creates search pattern")

-- Test 20: Case-insensitive with mixed case replacement
local result20 = str.string_replace("HeLLo WoRLd", "hello", "Hi", true)
assert_eq(result20, "Hi WoRLd")
print("✓ Test 20: Case-insensitive preserves replacement case")

print("\n✅ All string_replace tests passed!")

