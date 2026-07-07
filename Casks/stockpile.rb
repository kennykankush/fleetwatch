cask "stockpile" do
  version "0.1.1"
  sha256 "6a5b1583d632531851f77fa93c633127a74838b3db1d0d9df9b8bee6df3ced50"

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
