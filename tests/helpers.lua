-- Shared expectations for mini.test cases.
local H = {}

H.eq = MiniTest.expect.equality
H.neq = MiniTest.expect.no_equality

H.expect_truthy = MiniTest.new_expectation("truthy value", function(value)
  return value and true or false
end, function(value)
  return "Observed: " .. vim.inspect(value)
end)

-- `plain` skips Lua pattern magic, like string.find's fourth argument.
H.expect_match = MiniTest.new_expectation("string matching", function(str, pattern, plain)
  return type(str) == "string" and str:find(pattern, 1, plain) ~= nil
end, function(str, pattern)
  return "Pattern: " .. vim.inspect(pattern) .. "\nObserved string: " .. vim.inspect(str)
end)

H.expect_no_match = MiniTest.new_expectation("string not matching", function(str, pattern, plain)
  return type(str) == "string" and str:find(pattern, 1, plain) == nil
end, function(str, pattern)
  return "Pattern: " .. vim.inspect(pattern) .. "\nObserved string: " .. vim.inspect(str)
end)

return H
