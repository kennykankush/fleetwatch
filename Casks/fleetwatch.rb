cask "fleetwatch" do
  version "0.6.0"
  sha256 "ca315421dfab67d2880492b73e55573f7d2e8f93b0c29ae0eb0b60fe784ed5a1"

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
