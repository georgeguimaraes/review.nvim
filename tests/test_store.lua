local H = dofile("tests/helpers.lua")
local eq, neq = H.eq, H.neq

local store = require("review.store")

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      store.clear()
    end,
  },
})

T["add"] = MiniTest.new_set()

T["add"]["creates a comment with generated id"] = function()
  local comment = store.add("file.lua", 10, "issue", "Fix this")
  neq(comment.id, nil)
  eq("file.lua", comment.file)
  eq(10, comment.line)
  eq("issue", comment.type)
  eq("Fix this", comment.text)
end

T["add"]["stores comments by file"] = function()
  store.add("a.lua", 1, "note", "Note 1")
  store.add("a.lua", 2, "note", "Note 2")
  store.add("b.lua", 1, "issue", "Issue 1")

  eq(2, #store.get_for_file("a.lua"))
  eq(1, #store.get_for_file("b.lua"))
end

T["get_at_line"] = MiniTest.new_set()

T["get_at_line"]["returns comment at specific line"] = function()
  store.add("file.lua", 10, "issue", "At line 10")
  store.add("file.lua", 20, "note", "At line 20")

  local comment = store.get_at_line("file.lua", 10)
  neq(comment, nil)
  eq("At line 10", comment.text)
end

T["get_at_line"]["returns nil when no comment at line"] = function()
  store.add("file.lua", 10, "issue", "At line 10")
  eq(store.get_at_line("file.lua", 15), nil)
end

T["update"] = MiniTest.new_set()

T["update"]["updates comment text"] = function()
  local comment = store.add("file.lua", 10, "issue", "Original")
  local success = store.update(comment.id, "Updated")

  eq(success, true)
  eq("Updated", store.get(comment.id).text)
end

T["update"]["returns false for non-existent id"] = function()
  eq(store.update("fake_id", "text"), false)
end

T["delete"] = MiniTest.new_set()

T["delete"]["removes comment"] = function()
  local comment = store.add("file.lua", 10, "issue", "Delete me")
  eq(1, store.count())

  local success = store.delete(comment.id)
  eq(success, true)
  eq(0, store.count())
end

T["delete"]["returns false for non-existent id"] = function()
  eq(store.delete("fake_id"), false)
end

T["get_all"] = MiniTest.new_set()

T["get_all"]["returns all comments sorted by file and line"] = function()
  store.add("b.lua", 20, "note", "B20")
  store.add("a.lua", 10, "note", "A10")
  store.add("a.lua", 5, "note", "A5")

  local all = store.get_all()
  eq(3, #all)
  eq("A5", all[1].text)
  eq("A10", all[2].text)
  eq("B20", all[3].text)
end

T["count"] = MiniTest.new_set()

T["count"]["returns total comment count"] = function()
  eq(0, store.count())
  store.add("a.lua", 1, "note", "1")
  store.add("b.lua", 1, "note", "2")
  eq(2, store.count())
end

T["side awareness"] = MiniTest.new_set()

T["side awareness"]["stores side field on add"] = function()
  local c = store.add("file.lua", 10, "note", "old side", nil, "old")
  eq("old", c.side)
end

T["side awareness"]["defaults side to new"] = function()
  local c = store.add("file.lua", 10, "note", "no side")
  eq("new", c.side)
end

T["side awareness"]["get_at_line filters by side"] = function()
  store.add("file.lua", 10, "note", "old comment", nil, "old")
  store.add("file.lua", 10, "issue", "new comment", nil, "new")

  local old = store.get_at_line("file.lua", 10, "old")
  neq(old, nil)
  eq("old comment", old.text)

  local new = store.get_at_line("file.lua", 10, "new")
  neq(new, nil)
  eq("new comment", new.text)
end

T["side awareness"]["get_at_line without side returns first match"] = function()
  store.add("file.lua", 10, "note", "old comment", nil, "old")
  local c = store.get_at_line("file.lua", 10)
  neq(c, nil)
  eq("old comment", c.text)
end

T["side awareness"]["get_overlapping filters by side"] = function()
  store.add("file.lua", 5, "note", "old range", 15, "old")
  store.add("file.lua", 5, "issue", "new range", 15, "new")

  local old = store.get_overlapping("file.lua", 8, 12, "old")
  neq(old, nil)
  eq("old range", old.text)

  local new = store.get_overlapping("file.lua", 8, 12, "new")
  neq(new, nil)
  eq("new range", new.text)
end

T["side awareness"]["get_for_file filters by side"] = function()
  store.add("file.lua", 5, "note", "old", nil, "old")
  store.add("file.lua", 10, "issue", "new", nil, "new")

  local old_comments = store.get_for_file("file.lua", "old")
  eq(1, #old_comments)
  eq("old", old_comments[1].text)

  local new_comments = store.get_for_file("file.lua", "new")
  eq(1, #new_comments)
  eq("new", new_comments[1].text)
end

T["side awareness"]["get_for_file without side returns all"] = function()
  store.add("file.lua", 5, "note", "old", nil, "old")
  store.add("file.lua", 10, "issue", "new", nil, "new")

  local all = store.get_for_file("file.lua")
  eq(2, #all)
end

T["side awareness"]["get_for_file with side includes file-level comments"] = function()
  store.add("file.lua", 0, "note", "file comment")
  store.add("file.lua", 10, "issue", "new side", nil, "new")
  store.add("file.lua", 10, "note", "old side", nil, "old")

  local old_comments = store.get_for_file("file.lua", "old")
  eq(2, #old_comments)

  local new_comments = store.get_for_file("file.lua", "new")
  eq(2, #new_comments)
end

T["side awareness"]["comments on different sides at same line don't conflict"] = function()
  store.add("file.lua", 10, "note", "old note", nil, "old")
  store.add("file.lua", 10, "issue", "new issue", nil, "new")

  local old = store.get_at_line("file.lua", 10, "old")
  local new = store.get_at_line("file.lua", 10, "new")
  neq(old, nil)
  neq(new, nil)
  neq(old.text, new.text)
end

return T
