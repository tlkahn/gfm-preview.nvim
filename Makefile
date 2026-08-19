.PHONY: test test-file

# Run the full plenary.busted suite headlessly.
test:
	nvim --headless -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}" \
		-c "qa!"

# Run a single spec file: make test-file FILE=tests/preprocess/mermaid_spec.lua
test-file:
	nvim --headless -u tests/minimal_init.lua \
		-c "PlenaryBustedFile $(FILE)" \
		-c "qa!"
