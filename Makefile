.PHONY: test test-file test-e2e test-all deps

NVIM_TEST = nvim --headless --noplugin -u tests/minimal_init.lua

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
