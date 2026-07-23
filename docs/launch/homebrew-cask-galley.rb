# NOT READY TO SUBMIT. See docs/launch/CHECKLIST.md.
#
# Homebrew requires a Developer ID signed, notarized .app inside the cask's
# zip/dmg, or its CI (the "audit" and "livecheck" bots plus Gatekeeper checks
# on install) will flag or reject the submission. The current GitHub release
# asset (Galley-1.1.0-preview.zip) is an UNSIGNED preview build made for this
# repo's own Releases page, not for Homebrew.
#
# Once docs/DISTRIBUTION.md's notarize step is done and a signed release
# artifact exists:
#   1. shasum -a 256 <notarized-zip> and drop the hash in below
#   2. brew audit --new --strict --online Casks/galley.rb (from a
#      homebrew-cask fork, this file moved to Casks/galley.rb)
#   3. brew style --fix Casks/galley.rb
#   4. Open a PR against Homebrew/homebrew-cask
#
# The cask NAME "galley" was confirmed unclaimed via
# formulae.brew.sh/cask/galley (2026-07-22) — claim it with this first PR.

cask "galley" do
  version "1.1.0"
  sha256 "REPLACE-WITH-SHA256-OF-NOTARIZED-ZIP"

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
