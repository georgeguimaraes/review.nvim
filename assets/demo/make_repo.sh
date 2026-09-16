#!/bin/sh
# Creates a throwaway git repo with a small diff for the README demo.
# Usage: assets/demo/make_repo.sh <dir>
set -e
dir="$1"
rm -rf "$dir"
mkdir -p "$dir/src"
cd "$dir"
git init -q --initial-branch=main
cat > src/api.lua <<'LUA'
local http = require("http")
local json = require("json")

local M = {}

function M.fetch(url)
  local res = http.get(url)
  return res.body
end

function M.parse(body)
  return json.decode(body)
end

function M.get_user(id)
  local body = M.fetch("/users/" .. id)
  return M.parse(body)
end

return M
LUA
cat > src/utils.lua <<'LUA'
local M = {}

function M.trim(s)
  return s:match("^%s*(.-)%s*$")
end

return M
LUA
git add . && git -c user.name=demo -c user.email=demo@example.com -c commit.gpgsign=false commit -q -m "initial"
cat > src/api.lua <<'LUA'
local http = require("http")
local json = require("json")

local M = {}

function M.fetch(url)
  local res = http.get(url)
  if not res then
    error("request failed: " .. url)
  end
  return res.body
end

function M.parse(body)
  local ok, data = pcall(json.decode, body)
  if not ok then
    return nil
  end
  return data
end

function M.get_user(id)
  local body = M.fetch("/users/" .. id)
  local user = M.parse(body)
  if user then
    user.name = user.name:upper()
  end
  return user
end

return M
LUA
cat > src/utils.lua <<'LUA'
local M = {}

function M.trim(s)
  if not s then return "" end
  return s:match("^%s*(.-)%s*$")
end

function M.split(s, sep)
  return vim.split(s, sep)
end

return M
LUA
