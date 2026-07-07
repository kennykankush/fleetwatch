cask "stockpile" do
  version "0.1.4"
  sha256 "8b4dba53221e90cc4462234642271f5ac3b785f8eb6da2854a0fe1d277fba186"

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
