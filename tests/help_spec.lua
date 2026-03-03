local keymaps = require("review.keymaps")
local t = keymaps._test

describe("review.keymaps help", function()
  describe("format_key", function()
    it("passes through plain keys", function()
      assert.equals("i", t.format_key("i"))
      assert.equals("q", t.format_key("q"))
      assert.equals("]n", t.format_key("]n"))
      assert.equals("[n", t.format_key("[n"))
    end)

    it("strips angle brackets from special keys", function()
      assert.equals("Tab", t.format_key("<Tab>"))
      assert.equals("S-Tab", t.format_key("<S-Tab>"))
      assert.equals("Esc", t.format_key("<Esc>"))
    end)

    it("converts C- to Ctrl-", function()
      assert.equals("Ctrl-r", t.format_key("<C-r>"))
      assert.equals("Ctrl-s", t.format_key("<C-s>"))
    end)

    it("leaves <leader> as-is", function()
      assert.equals("<leader>", t.format_key("<leader>"))
    end)

    it("leaves leader-prefixed combos as-is", function()
      assert.equals("<leader>cn", t.format_key("<leader>cn"))
    end)
  end)

  describe("add_section", function()
    it("adds title and formatted entries", function()
      local entries = {
        { key = "i", desc = "Add comment" },
        { key = "e", desc = "Edit comment" },
      }
      local lines = {}
      t.add_section(entries, "Comments", lines, 5)

      assert.equals(4, #lines)
      assert.equals("", lines[1])
      assert.equals("  Comments", lines[2])
      assert.matches("i", lines[3])
      assert.matches("Add comment", lines[3])
      assert.matches("e", lines[4])
      assert.matches("Edit comment", lines[4])
    end)

    it("skips empty sections", function()
      local lines = {}
      t.add_section({}, "Empty", lines, 5)
      assert.equals(0, #lines)
    end)

    it("aligns columns based on max key width", function()
      local entries = {
        { key = "i", desc = "Short" },
        { key = "Ctrl-r", desc = "Long key" },
      }
      local lines = {}
      t.add_section(entries, "Test", lines, 6)

      -- Both descriptions should start at the same column
      local desc_col_1 = lines[3]:find("Short")
      local desc_col_2 = lines[4]:find("Long key")
      assert.equals(desc_col_1, desc_col_2)
    end)
  end)

  describe("is_enabled", function()
    it("returns true for string keys", function()
      assert.is_true(t.is_enabled("i"))
      assert.is_true(t.is_enabled("<C-r>"))
    end)

    it("returns false for disabled keys", function()
      assert.is_false(t.is_enabled(false))
      assert.is_false(t.is_enabled(nil))
      assert.is_false(t.is_enabled(""))
    end)
  end)
end)
