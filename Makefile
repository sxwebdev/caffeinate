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

# Resolved from the keychain so no personal identifier is committed.
# Override with: make install SIGN_IDENTITY="Developer ID Application: ..."
SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | \
	sed -n 's/.*"\(.*\)".*/\1/p' | head -1)
ifeq ($(strip $(SIGN_IDENTITY)),)
SIGN_IDENTITY := -
endif

TEAM_ID ?= $(shell security find-certificate -c "$(SIGN_IDENTITY)" -p 2>/dev/null | \
	openssl x509 -noout -subject 2>/dev/null | tr ',' '\n' | sed -n 's/.*OU=//p' | head -1)

.PHONY: all build test install uninstall run stop clean release

all: build

## Run the unit tests
test:
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'platform=macOS' \
		-derivedDataPath $(BUILD_DIR) \
		CODE_SIGNING_ALLOWED=NO

## Build a signed Release into ./build
build:
	xcodebuild -configuration $(CONFIG) -project $(PROJECT) -scheme $(SCHEME) \
		-derivedDataPath $(BUILD_DIR) \
		CODE_SIGN_STYLE=Manual \
		CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)" \
		DEVELOPMENT_TEAM="$(TEAM_ID)" \
		PROVISIONING_PROFILE_SPECIFIER="" \
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
	@echo "Installed to $(INSTALLED) (signed as: $(SIGN_IDENTITY))"
	open "$(INSTALLED)"

## Launch the installed app
run:
	@test -d "$(INSTALLED)" || { echo "Not installed. Run: make install"; exit 1; }
	open "$(INSTALLED)"

## Quit the running app
stop:
	-@pkill -x $(APP_NAME) 2>/dev/null || true

## Remove the app and its sandbox container
uninstall:
	-@pkill -x $(APP_NAME) 2>/dev/null || true
	rm -rf "$(INSTALLED)"
	rm -rf "$(CONTAINER)"
	@echo "Removed $(INSTALLED)"

clean:
	rm -rf $(BUILD_DIR)

## Tag and push a release
release:
	@if [ -z "$(TAG)" ]; then echo "Usage: make release TAG=v1.2.3"; exit 1; fi
	git tag -a $(TAG) -m "Release $(TAG)"
	git push origin $(TAG)
