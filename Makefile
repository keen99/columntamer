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

.PHONY: build run release package clean install-tools show-sign uninstall tag tag-build tag-push bump-after-release

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
	$(MAKE) tag-build
	$(MAKE) clean
	scripts/build.sh package
	$(MAKE) tag-push
	$(MAKE) bump-after-release

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

tag-build:
	@v=$$(cat VERSION); \
	echo "=== Tagging v$$v (local) ==="; \
	if git rev-parse "v$$v" >/dev/null 2>&1; then \
	  cur=$$(git rev-list -n1 "v$$v"); \
	  new=$$(git rev-parse HEAD); \
	  echo "tag v$$v exists at $$cur"; \
	  echo "HEAD = $$new"; \
	  read -p "force re-tag at HEAD? [y/N] " ans; \
	  if [[ "$${ans:-N}" == "y" || "$${ans:-N}" == "Y" ]]; then \
	    git tag -f -a "v$$v" -m "Release v$$v"; \
	  else \
	    echo "keeping existing tag"; \
	  fi; \
	else \
	  git tag -a "v$$v" -m "Release v$$v"; \
	fi

tag-push:
	@v=$$(cat VERSION); \
	echo "=== Pushing tag v$$v + GitHub release ==="; \
	if git ls-remote --exit-code --tags origin "v$$v" >/dev/null 2>&1; then \
	  read -p "tag v$$v exists on remote. force push? [y/N] " ans; \
	  if [[ "$${ans:-N}" == "y" || "$${ans:-N}" == "Y" ]]; then \
	    git push --force origin "v$$v"; \
	  else \
	    echo "skipping remote tag push"; \
	  fi; \
	else \
	  git push origin "v$$v"; \
	fi; \
	if gh release view "v$$v" >/dev/null 2>&1; then \
	  gh release upload "v$$v" "build/ColumnTamer-$$v.pkg" --clobber; \
	else \
	  gh release create "v$$v" --title "v$$v" --notes "See README." "build/ColumnTamer-$$v.pkg"; \
	fi; \
	echo "DONE: https://github.com/keen99/columntamer/releases/tag/v$$v"

bump-after-release:
	@v=$$(cat VERSION); \
	major=$$(echo "$$v" | cut -d. -f1); \
	minor=$$(echo "$$v" | cut -d. -f2); \
	patch=$$(echo "$$v" | cut -d. -f3); \
	patch=$$((patch + 1)); \
	new="$$major.$$minor.$$patch"; \
	echo "$$new" > VERSION; \
	git add VERSION BUILD_NUMBER; \
	git commit -m "chore: bump version $$v -> $$new (post-release)"; \
	echo "=== VERSION bumped $$v -> $$new, committed ==="; \
	echo "next dev builds: $$new-dev"
