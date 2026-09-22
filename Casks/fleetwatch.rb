cask "fleetwatch" do
  version "0.5.0"
  sha256 "ee564f3fc08e264aaf0e27134df78c8b350728e43d69e71304afb786a1332f01"

  url "https://github.com/kennykankush/fleetwatch/releases/download/v#{version}/Fleetwatch-#{version}.zip"
  name "Fleetwatch"
  desc "Health & hardware monitor for your fleet of machines"
  homepage "https://github.com/kennykankush/fleetwatch"

  depends_on macos: ">= :tahoe"

  app "Fleetwatch.app"

  zap trash: [
    "~/Library/Application Support/Fleetwatch",
    "~/Library/Preferences/com.hadimulia.fleetwatch.plist",
    "~/Library/Group Containers/483LU3J5WJ.com.hadimulia.fleetwatch",
  ]
end
