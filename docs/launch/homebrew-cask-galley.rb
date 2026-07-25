# Signed, notarized, and stapled. Verified: `spctl -a -vvv` reports
# "accepted, source=Notarized Developer ID"; `stapler validate` passes.
#
# `brew style` and `brew audit --cask --new galley` both pass except for
# one thing that isn't fixable here: "GitHub repository not notable enough
# (<30 forks, <30 watchers and <75 stars)". Homebrew gates new casks on
# the source repo's traction, not the cask itself — this needs the repo to
# pick up stars first (a fork is sitting ready at JessieSalas/homebrew-cask
# for whenever that's true). Once it clears that bar:
#   1. Copy this file to Casks/g/galley.rb in a homebrew-cask fork/clone
#   2. brew style --fix Casks/g/galley.rb
#   3. brew audit --cask --new galley (with it tapped locally)
#   4. Open a PR against Homebrew/homebrew-cask
#
# The cask NAME "galley" was confirmed unclaimed via
# formulae.brew.sh/cask/galley (2026-07-22) — claim it with this first PR.

cask "galley" do
  version "1.1.1"
  sha256 "c3f4751a3f0fe93bc265274cd10741919e2de3ab0aecdfab7383e66980254b7b"

  url "https://github.com/JessieSalas/galley/releases/download/v#{version}/Galley-#{version}.zip",
      verified: "github.com/JessieSalas/galley/"
  name "Galley"
  desc "Quiet, read-only Markdown reader"
  homepage "https://thesis.do/galley"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Galley.app"

  zap trash: [
    "~/Library/Containers/do.thesis.galley",
    "~/Library/Preferences/do.thesis.galley.plist",
    "~/Library/Saved Application State/do.thesis.galley.savedState",
  ]
end
