cask "fleetwatch" do
  version "0.8.0"
  sha256 "4adaab785cbace4c365c600d70237f49b3189b99e8057afdb8ae5794a8716052"

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
