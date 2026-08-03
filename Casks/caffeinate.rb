cask "caffeinate" do
  # These two lines are rewritten by `make bump-cask`, which the release workflow
  # runs after it has uploaded the build. Until the first tag is pushed they point
  # at nothing, so `brew install` fails on the download rather than installing
  # something unexpected.
  version "1.0.0"
  sha256 "decbe2245d641deafeb647f42564455a20305fbb29c98da5b4ee4f0a94343d1e"

  url "https://github.com/sxwebdev/caffeinate/releases/download/v#{version}/Caffeinate-#{version}.zip"
  name "Caffeinate"
  desc "Menu bar app that prevents idle sleep"
  homepage "https://github.com/sxwebdev/caffeinate"

  livecheck do
    url :url
    strategy :github_latest
  end

  # A bare symbol already means ">= this version"; spelling the comparator out is
  # deprecated. Big Sur is the app's own deployment target.
  depends_on macos: :big_sur

  app "Caffeinate.app"

  # The build is signed ad hoc: the project has no Apple Developer certificate, so
  # there is no Developer ID to sign with and nothing to notarize with either.
  # Gatekeeper refuses to launch a quarantined ad-hoc bundle, and Homebrew attaches
  # that flag to every download, so without this the app can only be started through
  # System Settings > Privacy & Security — again after every upgrade. Tapping this
  # repository and running `brew trust` on it is the point where that is agreed to.
  # `xattr -d -r` exits 0 when the attribute is already absent, so this is a no-op
  # if a future build is properly signed.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-d", "-r", "com.apple.quarantine", "#{appdir}/Caffeinate.app"]
  end

  # Start at login is deliberately left alone. Homebrew runs the uninstall stanza on
  # upgrades as well as on removals, so unregistering the login item here would
  # quietly switch the setting off every time a new version landed. Turn it off in
  # the app's own menu before uninstalling, or remove the entry afterwards in
  # System Settings > General > Login Items.
  uninstall quit: "dev.sxwebdev.caffeinate"

  zap trash: [
    "~/Library/Containers/dev.sxwebdev.caffeinate",
    "~/Library/Preferences/dev.sxwebdev.caffeinate.plist",
  ]
end
