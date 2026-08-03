APP_NAME     := Caffeinate
BUNDLE_ID    := dev.sxwebdev.caffeinate
PROJECT      := Caffeinate.xcodeproj
SCHEME       := Caffeinate
CONFIG       := Release
BUILD_DIR    := build
APP_BUNDLE   := $(BUILD_DIR)/Build/Products/$(CONFIG)/$(APP_NAME).app
INSTALL_DIR  := /Applications
INSTALLED    := $(INSTALL_DIR)/$(APP_NAME).app
ENTITLEMENTS := $(APP_NAME)/$(APP_NAME).entitlements
CONTAINER    := $(HOME)/Library/Containers/$(BUNDLE_ID)
DIST_DIR     := dist
CASK         := Casks/caffeinate.rb

# Empty by default, so a local build keeps whatever the project file says. The
# release workflow passes the tag as VERSION and its run number as BUILD_NUMBER,
# which is the only counter that grows on its own for CFBundleVersion.
VERSION      ?=
BUILD_NUMBER ?=
VERSION_SETTINGS := $(if $(strip $(VERSION)),MARKETING_VERSION=$(VERSION))
VERSION_SETTINGS += $(if $(strip $(BUILD_NUMBER)),CURRENT_PROJECT_VERSION=$(BUILD_NUMBER))

ZIP := $(DIST_DIR)/$(APP_NAME)-$(VERSION).zip

# Resolved from the keychain so no personal identifier is committed.
# Override with: make install SIGN_IDENTITY="Developer ID Application: ..."
SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | \
	sed -n 's/.*"\(.*\)".*/\1/p' | head -1)
ifeq ($(strip $(SIGN_IDENTITY)),)
SIGN_IDENTITY := -
endif

TEAM_ID ?= $(shell security find-certificate -c "$(SIGN_IDENTITY)" -p 2>/dev/null | \
	openssl x509 -noout -subject 2>/dev/null | tr ',' '\n' | sed -n 's/.*OU=//p' | head -1)

LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister

.PHONY: all build test install uninstall run stop clean release drop-app-products \
	dist bump-cask require-version

all: build

## Delete the built .app copies and their LaunchServices registrations
# xcodebuild registers every product it builds, so a copy left in the build directory
# shows up as an extra Caffeinate in Launchpad and Spotlight. Only the bundle itself is
# removed, not the compile cache, so builds stay incremental. Delete before
# unregistering: while a bundle is on disk the registration comes straight back, and it
# would then outlive the files as a ghost.
drop-app-products:
	@for cfg in Debug Release; do \
		rm -rf "$(BUILD_DIR)/Build/Products/$$cfg/$(APP_NAME).app"; \
	done
	-@for cfg in Debug Release; do \
		"$(LSREGISTER)" -u "$(BUILD_DIR)/Build/Products/$$cfg/$(APP_NAME).app" >/dev/null 2>&1 || true; \
	done

## Run the unit tests
test:
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'platform=macOS' \
		-derivedDataPath $(BUILD_DIR) \
		CODE_SIGNING_ALLOWED=NO
	@$(MAKE) --no-print-directory drop-app-products

## Build a signed Release into ./build
build:
	xcodebuild -configuration $(CONFIG) -project $(PROJECT) -scheme $(SCHEME) \
		-derivedDataPath $(BUILD_DIR) \
		CODE_SIGN_STYLE=Manual \
		CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)" \
		DEVELOPMENT_TEAM="$(TEAM_ID)" \
		PROVISIONING_PROFILE_SPECIFIER="" \
		$(VERSION_SETTINGS) \
		build

## Build, install into /Applications and launch
install: build
	-@pkill -x $(APP_NAME) 2>/dev/null || true
	rm -rf "$(INSTALLED)"
	cp -R "$(APP_BUNDLE)" "$(INSTALLED)"
	# Re-sign with our entitlements only: a Development certificate otherwise
	# leaves get-task-allow (debugger attach) in the installed bundle.
	codesign --force --sign "$(SIGN_IDENTITY)" \
		--entitlements "$(ENTITLEMENTS)" \
		--options runtime --timestamp=none "$(INSTALLED)"
	codesign --verify --strict "$(INSTALLED)"
	@$(MAKE) --no-print-directory drop-app-products
	@echo "Installed to $(INSTALLED) (signed as: $(SIGN_IDENTITY))"
	open "$(INSTALLED)"

## Launch the installed app
run:
	@test -d "$(INSTALLED)" || { echo "Not installed. Run: make install"; exit 1; }
	open "$(INSTALLED)"

## Quit the running app
stop:
	-@pkill -x $(APP_NAME) 2>/dev/null || true

## Remove the app, its login item and its sandbox container
uninstall:
	-@pkill -x $(APP_NAME) 2>/dev/null || true
	# Unregister the login item while the bundle still exists: only the app can do it,
	# so once it is deleted the entry lingers in Login Items with no way to remove it.
	# Older builds do not know the flag and would fall through to launching the GUI,
	# hanging make forever, so check that the binary actually advertises it first.
	@bin="$(INSTALLED)/Contents/MacOS/$(APP_NAME)"; \
		if [ ! -x "$$bin" ]; then \
			:; \
		elif ! grep -qa -- "--unregister-login-item" "$$bin"; then \
			echo "note: the installed build predates --unregister-login-item."; \
			echo "      If you had Start at Login on, turn it off in"; \
			echo "      System Settings > General > Login Items."; \
		elif ! "$$bin" --unregister-login-item; then \
			echo "warning: could not unregister the login item; remove it in"; \
			echo "         System Settings > General > Login Items."; \
		fi
	rm -rf "$(INSTALLED)"
	# Since macOS 14 another app's container counts as protected app data, so deleting
	# it needs Full Disk Access for whatever is running make. Report that instead of
	# failing the target: the app itself is already gone by this point.
	@if [ -d "$(CONTAINER)" ] && ! rm -rf "$(CONTAINER)" 2>/dev/null; then \
		echo "note: could not remove $(CONTAINER)."; \
		echo "      Grant Full Disk Access to your terminal, or remove it with sudo."; \
	fi
	@echo "Removed $(INSTALLED)"

## Remove build products, including their LaunchServices registrations
# xcodebuild runs a RegisterWithLaunchServices step on every build, so each build
# directory shows up as an extra Caffeinate in Launchpad and Spotlight. Delete the
# files first and unregister afterwards: while a bundle is still on disk the entry
# comes straight back, and it then outlives the files as a ghost. The product paths
# are spelled out rather than discovered with find, so a BUILD_DIR containing spaces
# cannot silently split into the wrong arguments.
clean:
	rm -rf "$(BUILD_DIR)"
	-@for cfg in Debug Release; do \
		"$(LSREGISTER)" -u "$(BUILD_DIR)/Build/Products/$$cfg/$(APP_NAME).app" >/dev/null 2>&1 || true; \
	done

require-version:
	@if [ -z "$(strip $(VERSION))" ]; then \
		echo "VERSION is required, e.g. make $(MAKECMDGOALS) VERSION=1.2.3"; exit 1; \
	fi

## Package the Release build as dist/Caffeinate-$(VERSION).zip plus its checksum
# ditto rather than zip: it keeps the bundle's symlinks and extended attributes, and
# a round trip that loses them invalidates the code signature. --keepParent puts
# Caffeinate.app at the root of the archive, which is what the cask's `app` stanza
# expects to find.
dist: require-version build
	rm -rf "$(DIST_DIR)"
	mkdir -p "$(DIST_DIR)"
	ditto -c -k --keepParent "$(APP_BUNDLE)" "$(ZIP)"
	@$(MAKE) --no-print-directory drop-app-products
	shasum -a 256 "$(ZIP)" | tee "$(ZIP).sha256"

## Point the Homebrew cask at VERSION and the checksum of the packaged zip
# Only the two generated lines are rewritten, so the rest of the cask stays
# hand-maintained. Both substitutions are read back afterwards: a silently
# unmatched sed would otherwise publish a release the cask still cannot install.
bump-cask: require-version
	@test -f "$(ZIP)" || { echo "$(ZIP) not found. Run: make dist VERSION=$(VERSION)"; exit 1; }
	@sha=$$(shasum -a 256 "$(ZIP)" | cut -d ' ' -f 1); \
		/usr/bin/sed -i '' \
			-e 's|^  version ".*"$$|  version "$(VERSION)"|' \
			-e "s|^  sha256 \".*\"$$|  sha256 \"$$sha\"|" \
			"$(CASK)"; \
		grep -q '^  version "$(VERSION)"$$' "$(CASK)" || \
			{ echo "$(CASK): the version line was not rewritten"; exit 1; }; \
		grep -q "^  sha256 \"$$sha\"$$" "$(CASK)" || \
			{ echo "$(CASK): the sha256 line was not rewritten"; exit 1; }
	ruby -c "$(CASK)" >/dev/null
	@echo "$(CASK) now describes $(VERSION)"

## Tag and push a release, which the release workflow builds and publishes
release:
	@if [ -z "$(TAG)" ]; then echo "Usage: make release TAG=v1.2.3"; exit 1; fi
	@# The workflow stamps CFBundleShortVersionString from the tag and Apple accepts
	@# at most three integers there, so reject anything else now rather than after
	@# the tag is already public.
	@printf '%s' "$(TAG)" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$$' || \
		{ echo "TAG must look like v1.2.3"; exit 1; }
	git tag -a $(TAG) -m "Release $(TAG)"
	git push origin $(TAG)
