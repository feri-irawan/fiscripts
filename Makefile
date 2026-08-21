.PHONY: help build check strict test validate

help:
	@echo "Available targets:"
	@echo "  make build    Rebuild generated artifacts under scripts/"
	@echo "  make check    Run the complete local validation and test suite"
	@echo "  make strict   Run the check suite requiring ShellCheck and all test runtimes"
	@echo "  make validate Validate all script manifests"
	@echo "  make test     Run tests only"

build:
	python3 tools/build.py

check:
	python3 tools/check.py

strict:
	python3 tools/check.py --strict

validate:
	python3 tools/validate-manifests.py

test:
	python3 tools/check.py
