cask "fleetwatch" do
  version "0.7.0"
  sha256 "f5327a54e3c5a495e5ea771c05616ea1ab06ed96145df3343e72cc1ac4e29e0d"

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
