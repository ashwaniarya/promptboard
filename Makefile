BIN_DIR ?= $(HOME)/.local/bin

.PHONY: build test run app cli install clean

build:
	swift build

test:
	swift test

run:
	swift run PromptBoardApp

app:
	./scripts/make-app.sh

cli:
	swift build -c release --product promptboard

install: cli
	install -d $(BIN_DIR)
	install .build/release/promptboard $(BIN_DIR)/promptboard

clean:
	rm -rf .build dist
