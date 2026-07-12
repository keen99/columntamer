# ColumnTamer Makefile --- thin router.
# All logic in scripts/. Signing auto-picked per AGENTS.md §Conventions.
# System-type tool (osax + LaunchAgent). Do NOT call build scripts directly.

# ── Signing auto-detect (Apple Dev → ad-hoc) ───────────────────────────────
SIGN_DEV_CERT := Apple Development
SIGN_IDENTITY := $(shell security find-identity -v -p codesigning 2>/dev/null \
	| grep "$(SIGN_DEV_CERT)" | head -1 \
	| sed 's/.*"\(.*\)".*/\1/')
ifeq ($(SIGN_IDENTITY),)
export SIGN_IDENTITY := -
export SIGN_TEAM :=
else
export SIGN_IDENTITY := $(SIGN_IDENTITY)
export SIGN_TEAM := $(shell security find-certificate -c "$(SIGN_DEV_CERT)" -p 2>/dev/null \
	| openssl x509 -noout -subject 2>/dev/null \
	| grep -oE 'OU=[A-Z0-9]+' | cut -d= -f2)
endif

.PHONY: build run release package clean install-tools show-sign uninstall tag

V := $(shell cat VERSION)

# One core script, 4 doors. No chain.
build:
	scripts/build.sh build

run:
	scripts/build.sh run

release:
	@echo "Current version: v$(V)"
	@read -p "New version (enter=keep v$(V)): " v; \
	  new=$${v:-$(V)}; \
	  echo "$$new" > VERSION; \
	  echo "Version set to v$$new"
	@if [ "$$(cat VERSION)" != "$(V)" ]; then \
	  git add VERSION; \
	  git commit -m "chore: bump version to v$$(cat VERSION)"; \
	fi
	$(MAKE) clean
	scripts/build.sh package
	$(MAKE) tag

package:
	scripts/build.sh package

uninstall:
	sudo scripts/uninstall.sh

clean:
	rm -rf build

install-tools:
	@echo "no xcodegen needed --- native clang/swiftc"

show-sign:
	@echo "SIGN_IDENTITY=[$$SIGN_IDENTITY]"
	@echo "SIGN_TEAM=[$$SIGN_TEAM]"

tag:
	@v=$$(cat VERSION); \
	echo "=== Tagging v$$v ==="; \
	if git rev-parse "v$$v" >/dev/null 2>&1; then \
	  echo "tag v$$v exists, skipping"; \
	else \
	  git tag -a "v$$v" -m "Release v$$v"; \
	  git push origin "v$$v"; \
	  echo "=== Creating GitHub release ==="; \
	  gh release create "v$$v" --title "v$$v" --notes "See README." "build/ColumnTamer-$$v.pkg"; \
	  echo "DONE: https://github.com/keen99/columntamer/releases/tag/v$$v"; \
	fi
