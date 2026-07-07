cask "stockpile" do
  version "0.1.0"
  sha256 "196db79ad55f3c9c3ead483dd5fb91a6d526f2e50b8c4dd6606c816766562dcc"

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
