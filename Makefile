# ColumnTamer Makefile — thin router.
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

.PHONY: build run release package clean install-tools show-sign uninstall

# One core script, 4 doors. No chain.
build:
	scripts/build.sh build

run:
	scripts/build.sh run

release:
	scripts/build.sh release

package:
	scripts/build.sh package

install:
	sudo scripts/install.sh

uninstall:
	sudo scripts/uninstall.sh

clean:
	rm -rf build

install-tools:
	@echo "no xcodegen needed — native clang/swiftc"

show-sign:
	@echo "SIGN_IDENTITY=[$$SIGN_IDENTITY]"
	@echo "SIGN_TEAM=[$$SIGN_TEAM]"
