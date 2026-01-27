local config = require("review.config")
local store = require("review.store")
local file = require("review.file")

local function read_file(path)
  local handle = io.open(path, "r")
  if not handle then
    return nil
  end
  local content = handle:read("*a")
  handle:close()
  return content
end

describe("review.file", function()
  local original_config
  local temp_dir
  local file_path

  before_each(function()
    original_config = vim.deepcopy(config.get())
    temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir, "p")
    config.setup({
      export = {
        file = {
          enabled = true,
          filename = "CODE_REVIEW.md",
          dir = temp_dir,
          import_on_open = true,
        },
      },
    })
    file_path = temp_dir .. "/CODE_REVIEW.md"
    store.clear()
  end)

  after_each(function()
    config.setup(original_config)
    store.clear()
    if temp_dir then
      vim.fn.delete(temp_dir, "rf")
    end
  end)

  it("writes markdown and reloads", function()
    store.add("src/main.lua", 12, "issue", "Fix this bug")

    local ok = file.write_from_store({ copy = false, close = false })
    assert.is_true(ok)

    store.clear()
    local loaded = file.load_into_store()
    assert.is_true(loaded)

    local all = store.get_all()
    assert.equals(1, #all)
    assert.matches("^comment_%d+_%d+$", all[1].id)
    assert.equals("src/main.lua", all[1].file)
    assert.equals(12, all[1].line)
    assert.equals("issue", all[1].type)
    assert.equals("Fix this bug", all[1].text)
  end)

  it("generates ids when markers are missing", function()
    local markdown = table.concat({
      "I reviewed your code and have the following comments. Please address them.",
      "",
      "Comment types: ISSUE (problems to fix), SUGGESTION (improvements), NOTE (observations), PRAISE (positive feedback)",
      "",
      "1. **[NOTE]** `src/app.lua:4` - Note without marker",
    }, "\n")

    local handle = io.open(file_path, "w")
    assert.is_truthy(handle)
    handle:write(markdown)
    handle:close()

    local loaded = file.load_into_store()
    assert.is_true(loaded)

    local all = store.get_all()
    assert.equals(1, #all)
    assert.matches("^comment_%d+_%d+$", all[1].id)
    assert.equals("note", all[1].type)
    assert.equals("src/app.lua", all[1].file)
    assert.equals(4, all[1].line)
    assert.equals("Note without marker", all[1].text)
  end)
end)
