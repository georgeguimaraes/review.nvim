local M = {}

---Normalize a file path for consistent storage/lookup
---@param path string
---@return string
function M.normalize_path(path)
  if not path then
    return path
  end
  path = path:gsub("^%./", "")
  path = path:gsub("/+$", "")
  return path
end

---@type table<string, string|false> git root by directory (false = not a repo)
local root_cache = {}

---Git root of `dir` (default: cwd), with symlinks resolved.
---@param dir? string
---@return string|nil
function M.git_root(dir)
  dir = dir or vim.fn.getcwd()
  local cached = root_cache[dir]
  if cached ~= nil then
    return cached or nil
  end
  local result = vim.fn.systemlist({ "git", "-C", dir, "rev-parse", "--show-toplevel" })
  local root = (vim.v.shell_error == 0 and result[1]) and (vim.uv.fs_realpath(result[1]) or result[1]) or false
  root_cache[dir] = root
  return root or nil
end

---Path of `path` relative to the git root of the cwd, nil when it lives
---outside that repository (or there is no repository).
---@param path string
---@return string|nil
function M.relative_to_root(path)
  local root = M.git_root()
  if not root or not path or path == "" then
    return nil
  end
  local abs = vim.uv.fs_realpath(vim.fn.fnamemodify(path, ":p")) or vim.fn.fnamemodify(path, ":p")
  if abs == root then
    return nil
  end
  if abs:sub(1, #root + 1) == root .. "/" then
    return M.normalize_path(abs:sub(#root + 2))
  end
  return nil
end

return M
