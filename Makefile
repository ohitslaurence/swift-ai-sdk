.PHONY: build test format format-check lint docs clean

build:
	swift build

test:
	swift test

format:
	swift format --recursive --in-place Sources/ Tests/

format-check:
	swift format lint --strict --recursive Sources/ Tests/

lint: format-check

docs:
	SDK_PATH="$$(xcrun --show-sdk-path)" && \
	mkdir -p .build/symbol-graphs .build/docc-output && \
	xcrun swift-symbolgraph-extract \
		-module-name AICore \
		-I .build/arm64-apple-macosx/debug/Modules \
		-output-dir .build/symbol-graphs \
		-pretty-print \
		-minimum-access-level public \
		-target arm64-apple-macosx14.0 \
		-sdk "$$SDK_PATH" && \
	xcrun docc convert Sources/AICore/Documentation.docc \
		--fallback-display-name AICore \
		--fallback-bundle-identifier com.example.aicore \
		--fallback-bundle-version 0.1.0 \
		--additional-symbol-graph-dir .build/symbol-graphs \
		--output-path .build/docc-output

clean:
	swift package clean
	rm -rf .build
