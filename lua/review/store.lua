local M = {}

local storage = require("review.storage")

---@class Comment
---@field id string
---@field file string
---@field line number
---@field type "note"|"suggestion"|"issue"|"praise"
---@field text string
---@field created_at number

---@type table<string, Comment[]>
M.comments = {}

local id_counter = 0
local loaded = false

---@return string
local function generate_id()
  id_counter = id_counter + 1
  return string.format("comment_%d_%d", os.time(), id_counter)
end

function M.generate_id()
  return generate_id()
end

local function persist()
  storage.save(M.comments)
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
---@return Comment
function M.add(file, line, type, text)
  if not M.comments[file] then
    M.comments[file] = {}
  end

  local comment = {
    id = generate_id(),
    file = file,
    line = line,
    type = type,
    text = text,
    created_at = os.time(),
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
---@return Comment[]
function M.get_for_file(file)
  return M.comments[file] or {}
end

---@param file string
---@param line number
---@return Comment|nil
function M.get_at_line(file, line)
  local comments = M.comments[file] or {}
  for _, comment in ipairs(comments) do
    if comment.line == line then
      return comment
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

---@param id string
---@return boolean
function M.delete(id)
  for file, comments in pairs(M.comments) do
    for i, comment in ipairs(comments) do
      if comment.id == id then
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

function M.replace_all(comments)
  M.comments = comments or {}
  id_counter = 0
  for _, comment_list in pairs(M.comments) do
    for _, comment in ipairs(comment_list) do
      local num = tonumber(comment.id and comment.id:match("comment_%d+_(%d+)"))
      if num and num > id_counter then
        id_counter = num
      end
    end
  end
  loaded = true
  storage.save(M.comments)
end

function M.clear()
  M.comments = {}
  id_counter = 0
  storage.clear()
end

return M
