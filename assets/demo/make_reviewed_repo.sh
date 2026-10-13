#!/bin/sh
# The demo repo plus two more changed files, for the reviewed-files demo.
# Usage: assets/demo/make_reviewed_repo.sh <dir>
set -e
dir="$1"
"$(dirname "$0")/make_repo.sh" "$dir"
cd "$dir"
cat > src/cache.lua <<'LUA'
local M = {}

local store = {}

function M.get(key)
  return store[key]
end

return M
LUA
cat > src/log.lua <<'LUA'
local M = {}

function M.info(msg)
  print(msg)
end

return M
LUA
git add src/cache.lua src/log.lua && git -c user.name=demo -c user.email=demo@example.com -c commit.gpgsign=false commit -q -m "cache and log"
cat > src/cache.lua <<'LUA'
local M = {}

local store = {}

function M.get(key)
  return store[key]
end

function M.set(key, value)
  store[key] = value
end

return M
LUA
cat > src/log.lua <<'LUA'
local M = {}

function M.info(msg)
  print("[info] " .. msg)
end

function M.warn(msg)
  print("[warn] " .. msg)
end

return M
LUA
