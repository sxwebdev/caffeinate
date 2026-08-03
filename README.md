# Caffeinate

A macOS menubar app to temporarily prevent the Mac from sleeping.

## How does it work

Clicking the status item — with either mouse button — opens a menu holding everything
the app does: the on/off switch, the mode, the auto-off timer, the launch options and
Quit. The icon is a coffee cup while Caffeinate is active and `zzz` while it is not.

While active, the app holds an IOKit power assertion. Two modes are available:

| Mode                  | Assertion                     | Equivalent      | Behaviour                                                                                       |
| --------------------- | ----------------------------- | --------------- | ----------------------------------------------------------------------------------------------- |
| Keep the display on   | `PreventUserIdleDisplaySleep` | `caffeinate -d` | The display stays lit, which also keeps the system awake.                                       |
| Let the display sleep | `PreventUserIdleSystemSleep`  | `caffeinate -i` | The display switches off on its own, the system keeps running. Useful for long background jobs. |

The icon carries only on/off; the mode is shown in the menu and in the status item's
tooltip. Encoding it in the icon as well meant swapping the drawn object rather than
its state, which read as an unrelated picture.

Both modes only block _idle_ sleep. Closing the lid, choosing Sleep from the Apple
menu, or running out of battery still puts the Mac to sleep. Verify the live state
with `pmset -g assertions | grep Caffeinate`.

**Auto-off timer.** Caffeinate can switch itself off after 15 minutes, 30 minutes,
1 hour, 2 hours, or any number of minutes up to a day entered via _Custom…_. The
deadline is handed to the kernel via the assertion's own
timeout, so the assertion is released even if the app is wedged or suspended — it
does not depend on a timer inside the process.

**Activate on launch.** Combined with _Start at login_ this brings the Mac up
already caffeinated after a reboot, which is useful for long unattended jobs.

## Localization

The interface ships in English, Russian, German, Spanish, French, Simplified Chinese,
Japanese and Arabic. macOS picks the language from the system preferences and falls
back to English for anything else.

Durations in the auto-off menu are rendered by `DateComponentsFormatter` rather than
from the strings files, so plural forms are the system's problem and an arbitrary
custom value is safe to display in every language.

To check a language without changing your system settings:

```sh
defaults write dev.sxwebdev.caffeinate AppleLanguages -array ru   # or: en
```

Remove the override again with
`defaults delete dev.sxwebdev.caffeinate AppleLanguages`.

## Requirements

The app requires macOS 11 or later to run. _Start at login_ needs macOS 13 or later; on
macOS 11 and 12 that menu entry is disabled and you can add the app to Login Items in
System Settings by hand.

## Installation

### Homebrew

```sh
brew tap sxwebdev/caffeinate https://github.com/sxwebdev/caffeinate
brew trust --tap sxwebdev/caffeinate
brew install --cask caffeinate
```

The cask lives in this repository instead of a separate `homebrew-*` one, which is why
the tap needs a URL. Homebrew will not load anything from a tap it has not been told to
trust, hence the second line.

`brew upgrade --cask caffeinate` installs newer versions. The release workflow bumps
the cask as soon as a tag is built, so `brew update` is enough to notice one.

Builds are signed ad hoc: the project has no Apple Developer certificate, so there is
no Developer ID to sign with and nothing to notarize with either, and Gatekeeper
refuses to launch a quarantined ad-hoc bundle. The cask therefore removes the
quarantine flag Homebrew attaches to every download — without that the app would have
to be approved in System Settings > Privacy & Security after every install and every
upgrade. Trusting the tap is the point at which you agree to that; if you would rather
not, build from source instead.

Removal:

```sh
brew uninstall --cask caffeinate          # leaves preferences behind
brew uninstall --zap --cask caffeinate    # also removes the sandbox container
```

Turn _Start at login_ off in the menu first if it was on. Homebrew runs a cask's
uninstall steps on upgrades too, so the cask deliberately leaves the login item alone —
otherwise every upgrade would quietly switch the setting off. Deleting the sandbox
container needs Full Disk Access for your terminal; without it Homebrew falls back to
`sudo`.

### From source

`make install` builds a signed Release, installs it into `/Applications` and launches
it. The signing identity is resolved from your keychain, falling back to an ad-hoc
signature when no certificate is present. Other targets: `make build`, `make test`,
`make run`, `make stop`, `make uninstall`, `make clean`.

### Download

The ZIP attached to each [release](https://github.com/sxwebdev/caffeinate/releases)
contains `Caffeinate.app`. Since it is only signed ad hoc, macOS will not open it until
the quarantine flag is gone:

```sh
xattr -d -r com.apple.quarantine /Applications/Caffeinate.app
```

## Releases

`make release TAG=v1.2.3` tags the current commit and pushes the tag; that is the whole
procedure. The release workflow then runs the tests, builds a universal Release with
`CFBundleShortVersionString` taken from the tag and `CFBundleVersion` from the workflow
run number, packages it with `ditto` so the signature survives, attaches the ZIP to a
GitHub release, and pushes the matching `Casks/caffeinate.rb` bump to `master`. Only
the built-in `GITHUB_TOKEN` is used — there are no secrets to configure and no Apple
account involved.

`make dist VERSION=1.2.3` builds the same ZIP locally if you want to look at one before
tagging.

## FAQ

**How do I quit?**

Click the menu bar item and choose Quit Caffeinate.

## TODO

Even if the lid is closed, prevent the Mac from sleeping. This probably requires root privileges.
