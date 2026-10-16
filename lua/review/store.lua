local M = {}

local storage = require("review.storage")

---@class Comment
---@field id string
---@field file string
---@field line number
---@field line_end? number
---@field side? "old"|"new"
---@field type "note"|"suggestion"|"issue"|"praise"
---@field text string
---@field created_at number
---@field branch? string branch checked out when the comment was made

---@type table<string, Comment[]>
M.comments = {}

local id_counter = 0
local loaded = false
-- Ids deleted since load, so a merge in persist() does not bring them back
local deleted = {}

---Unique across Neovims sharing the file: two that loaded the same comments
---resume from the same counter, so the process id tells their ids apart. The
---counter stays second, where load() reads it back.
---@return string
local function generate_id()
  id_counter = id_counter + 1
  return string.format("comment_%d_%d_%d", os.time(), id_counter, vim.uv.os_getpid())
end

-- Another writer (a second Neovim, or a tool sharing the file) may have saved
-- since load. Keep what it added: comments on disk that are neither in memory
-- nor deleted here join the in-memory store before it is written back.
local function merge_from_disk()
  local known = {}
  for _, comments in pairs(M.comments) do
    for _, comment in ipairs(comments) do
      known[comment.id] = true
    end
  end
  for file, comments in pairs(storage.load()) do
    if type(comments) == "table" then
      for _, comment in ipairs(comments) do
        if type(comment) == "table" and comment.id and not known[comment.id] and not deleted[comment.id] then
          M.comments[file] = M.comments[file] or {}
          table.insert(M.comments[file], comment)
          known[comment.id] = true
        end
      end
    end
  end
end

local function persist()
  merge_from_disk()
  storage.save(M.comments)
end

function M.reset()
  M.comments = {}
  id_counter = 0
  loaded = false
  deleted = {}
end

function M.load()
  if loaded then
    return
  end
  M.comments = storage.load()
  -- Update id_counter to avoid collisions
  for _, comments in pairs(M.comments) do
    for _, comment in ipairs(comments) do
      local num = tonumber(comment.id:match("comment_%d+_(%d+)"))
      if num and num > id_counter then
        id_counter = num
      end
    end
  end
  loaded = true
end

---@param file string
---@param line number
---@param type "note"|"suggestion"|"issue"|"praise"
---@param text string
---@param line_end? number
---@param side? "old"|"new"
---@return Comment
function M.add(file, line, type, text, line_end, side)
  if not M.comments[file] then
    M.comments[file] = {}
  end

  local comment = {
    id = generate_id(),
    file = file,
    line = line,
    line_end = (line_end and line_end ~= line) and line_end or nil,
    side = side or "new",
    type = type,
    text = text,
    created_at = os.time(),
    branch = storage.git_branch(),
  }

  table.insert(M.comments[file], comment)
  persist()
  return comment
end

---@param id string
---@return Comment|nil
function M.get(id)
  for _, comments in pairs(M.comments) do
    for _, comment in ipairs(comments) do
      if comment.id == id then
        return comment
      end
    end
  end
  return nil
end

---@param file string
---@param side? "old"|"new"
---@return Comment[]
function M.get_for_file(file, side)
  local comments = M.comments[file] or {}
  if not side then
    return comments
  end
  local filtered = {}
  for _, comment in ipairs(comments) do
    if comment.line == 0 or (comment.side or "new") == side then
      table.insert(filtered, comment)
    end
  end
  return filtered
end

---@param file string
---@return Comment|nil
function M.get_file_comment(file)
  local comments = M.comments[file] or {}
  for _, comment in ipairs(comments) do
    if comment.line == 0 then
      return comment
    end
  end
  return nil
end

---@param file string
---@param line number
---@param side? "old"|"new"
---@return Comment|nil
function M.get_at_line(file, line, side)
  local comments = M.comments[file] or {}
  for _, comment in ipairs(comments) do
    local line_end = comment.line_end or comment.line
    if line >= comment.line and line <= line_end then
      if not side or (comment.side or "new") == side then
        return comment
      end
    end
  end
  return nil
end

---@param file string
---@param start_line number
---@param end_line number
---@param side? "old"|"new"
---@return Comment|nil
function M.get_overlapping(file, start_line, end_line, side)
  local comments = M.comments[file] or {}
  for _, comment in ipairs(comments) do
    local c_end = comment.line_end or comment.line
    if comment.line <= end_line and c_end >= start_line then
      if not side or (comment.side or "new") == side then
        return comment
      end
    end
  end
  return nil
end

---@param id string
---@param text string
---@param new_type? "note"|"suggestion"|"issue"|"praise"
---@return boolean
function M.update(id, text, new_type)
  for _, comments in pairs(M.comments) do
    for _, comment in ipairs(comments) do
      if comment.id == id then
        comment.text = text
        if new_type then
          comment.type = new_type
        end
        persist()
        return true
      end
    end
  end
  return false
end

---Move a comment to new lines (used when the buffer it lives in was edited).
---@param id string
---@param line number
---@param line_end? number
---@return boolean
function M.move(id, line, line_end)
  local comment = M.get(id)
  if not comment then
    return false
  end
  comment.line = line
  comment.line_end = (line_end and line_end ~= line) and line_end or nil
  persist()
  return true
end

---@param id string
---@return boolean
function M.delete(id)
  for file, comments in pairs(M.comments) do
    for i, comment in ipairs(comments) do
      if comment.id == id then
        deleted[id] = true
        table.remove(comments, i)
        if #comments == 0 then
          M.comments[file] = nil
        end
        persist()
        return true
      end
    end
  end
  return false
end

---@return Comment[]
function M.get_all()
  local all = {}
  for _, comments in pairs(M.comments) do
    for _, comment in ipairs(comments) do
      table.insert(all, comment)
    end
  end
  table.sort(all, function(a, b)
    if a.file ~= b.file then
      return a.file < b.file
    end
    return a.line < b.line
  end)
  return all
end

---@return table<string, Comment[]>
function M.get_all_by_file()
  return M.comments
end

---@return number
function M.count()
  local count = 0
  for _, comments in pairs(M.comments) do
    count = count + #comments
  end
  return count
end

---Comments made on other branches than `branch`, grouped by branch name.
---@param branch string|nil
---@return table<string, number> counts by branch
function M.count_from_other_branches(branch)
  local counts = {}
  for _, comments in pairs(M.comments) do
    for _, comment in ipairs(comments) do
      if comment.branch and branch and comment.branch ~= branch then
        counts[comment.branch] = (counts[comment.branch] or 0) + 1
      end
    end
  end
  return counts
end

---Archive the persisted file and start over. Nothing is deleted outright.
---@return string|nil archived file path
function M.archive_and_clear()
  local archived = storage.archive()
  M.reset()
  storage.clear()
  require("review.reviewed").reset()
  return archived
end

function M.clear()
  M.archive_and_clear()
end

return M
