cask "fleetwatch" do
  version "0.8.1"
  sha256 "876906798cb52fff7b83be1836db4429cccddce2e2f80234ed3b996f4cb2bb93"

  url "https://github.com/kennykankush/fleetwatch/releases/download/v#{version}/Fleetwatch-#{version}.zip"
  name "Fleetwatch"
  desc "Health & hardware monitor for your fleet of machines"
  homepage "https://github.com/kennykankush/fleetwatch"

  depends_on macos: :tahoe

  app "Fleetwatch.app"

  zap trash: [
    "~/Library/Application Support/Fleetwatch",
    "~/Library/Preferences/com.hadimulia.fleetwatch.plist",
    "~/Library/Group Containers/483LU3J5WJ.com.hadimulia.fleetwatch",
  ]
end
