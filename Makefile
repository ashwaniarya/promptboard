.PHONY: build test run app clean

build:
	swift build

test:
	swift test

run:
	swift run

app:
	./scripts/make-app.sh

clean:
	rm -rf .build dist
