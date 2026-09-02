.PHONY: test test-live

# Run the whole suite (see tests/run.sh). `make test T=watcher` runs one file.
test:
	@tests/run.sh $(T)

# Also run the checks that open real windows (needs a Hyprland session)
test-live:
	@LEXTERN_TEST_LIVE=1 tests/run.sh $(T)
