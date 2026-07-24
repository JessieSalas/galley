# Signed, notarized, and stapled. Verified: `spctl -a -vvv` reports
# "accepted, source=Notarized Developer ID"; `stapler validate` passes.
#
# To submit:
#   1. brew audit --new --strict --online Casks/galley.rb (from a
#      homebrew-cask fork, this file moved to Casks/galley.rb)
#   2. brew style --fix Casks/galley.rb
#   3. Open a PR against Homebrew/homebrew-cask
#
# The cask NAME "galley" was confirmed unclaimed via
# formulae.brew.sh/cask/galley (2026-07-22) — claim it with this first PR.

cask "galley" do
  version "1.1.0"
  sha256 "80fe56d364fc6e6c723e76d715f19c77e18be5f5f30d849cb401c69a667adca8"

  url "https://github.com/JessieSalas/galley/releases/download/v#{version}/Galley-#{version}.zip"
  name "Galley"
  desc "Quiet, read-only Markdown reader for the Mac"
  homepage "https://thesis.do/galley"

  auto_updates false
  depends_on macos: ">= :sonoma"

  app "Galley.app"

  zap trash: [
    "~/Library/Containers/do.thesis.galley",
    "~/Library/Preferences/do.thesis.galley.plist",
    "~/Library/Saved Application State/do.thesis.galley.savedState",
  ]
end
