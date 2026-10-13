local H = dofile("tests/helpers.lua")
local eq = H.eq

local reviewed = require("review.reviewed")

local T = MiniTest.new_set()

local function sides(data, file)
  return { reviewed.sides(data, file) }
end

T["sides"] = MiniTest.new_set()

T["sides"]["working tree: unstaged compares the index with the file on disk"] = function()
  eq(sides({}, { path = "a.lua", group = "unstaged" }), { ":0:a.lua" })
end

T["sides"]["working tree: staged compares HEAD (old path) with the index"] = function()
  eq(sides({}, { path = "new.lua", old_path = "old.lua", group = "staged" }), { "HEAD:old.lua", ":0:new.lua" })
end

T["sides"]["conflicts compare the two stages"] = function()
  eq(sides({ base_revision = "abc" }, { path = "a.lua", group = "conflicts" }), { ":2:a.lua", ":3:a.lua" })
end

T["sides"]["revision mode uses the target, or the file on disk for WORKING"] = function()
  local file = { path = "new.lua", old_path = "old.lua", group = "unstaged" }
  eq(sides({ base_revision = "abc", target_revision = "def" }, file), { "abc:old.lua", "def:new.lua" })
  eq(sides({ base_revision = "abc", target_revision = "WORKING" }, file), { "abc:old.lua" })
  eq(sides({ base_revision = "abc" }, file), { "abc:old.lua" })
end

return T
