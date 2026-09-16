.PHONY: test test-file test-e2e test-all deps demo

# Tests persist comments via stdpath("data"); point that at a scratch dir.
TEST_HOME = $(CURDIR)/.tests
NVIM_TEST = XDG_DATA_HOME=$(TEST_HOME)/data XDG_STATE_HOME=$(TEST_HOME)/state XDG_CACHE_HOME=$(TEST_HOME)/cache XDG_CONFIG_HOME=$(TEST_HOME)/config \
	nvim --headless --noplugin -u tests/minimal_init.lua

# Unit tests: tests/test_*.lua, run in-process
test: deps/mini.test
	$(NVIM_TEST) -c "lua MiniTest.run({ collect = { find_files = function() return vim.fn.globpath('tests', 'test_*.lua', true, true) end } })"

# Single file (unit or e2e): make test-file FILE=tests/test_store.lua
test-file: deps/mini.test
	$(NVIM_TEST) -c "lua MiniTest.run_file('$(FILE)')"

# End-to-end tests: real codediff.nvim + nui.nvim in a child Neovim
test-e2e: deps
	$(NVIM_TEST) -c "lua MiniTest.run({ collect = { find_files = function() return vim.fn.globpath('tests/e2e', 'test_*.lua', true, true) end } })"

test-all: deps
	$(NVIM_TEST) -c "lua MiniTest.run()"

DEPS = deps/mini.test deps/codediff.nvim deps/nui.nvim

# Clone deps and let codediff fetch its native library and watcher binary up
# front, so the first :Review inside a test doesn't block on installer output.
deps: $(DEPS)
	nvim --headless --noplugin -u tests/e2e/child_init.lua \
	  -c "lua require('codediff.core.diff')" \
	  -c "lua local done = false; require('codediff.core.installer.watcher').ensure(function() done = true end); vim.wait(120000, function() return done end, 100)" \
	  -c "qa!"

deps/mini.test:
	git clone --depth 1 https://github.com/nvim-mini/mini.test $@

deps/codediff.nvim:
	git clone --depth 1 https://github.com/esmuellert/codediff.nvim $@

deps/nui.nvim:
	git clone --depth 1 https://github.com/MunifTanjim/nui.nvim $@

# README demo gif (needs vhs 0.11: https://github.com/charmbracelet/vhs)
demo: deps deps/tokyonight.nvim
	vhs assets/demo.tape

deps/tokyonight.nvim:
	git clone --depth 1 https://github.com/folke/tokyonight.nvim $@
