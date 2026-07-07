cask "stockpile" do
  version "0.1.3"
  sha256 "b945a9add9fb750ac780beadc19184a5311a19c988c2f46033ceaf4cebf37460"

  url "https://github.com/kennykankush/stockpile/releases/download/v#{version}/Stockpile-#{version}.zip"
  name "Stockpile"
  desc "Storage transparency for macOS — your disk, explained, not just displayed"
  homepage "https://github.com/kennykankush/stockpile"

  depends_on macos: ">= :tahoe"

  app "Stockpile.app"

  zap trash: [
    "~/Library/Application Support/Stockpile",
  ]
end
