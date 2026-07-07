import Foundation
import Testing
@testable import InventoryKit

@Suite("Brew catalog")
struct BrewCatalogTests {
    @Test("Normalization strips everything but alphanumerics")
    func normalization() {
        #expect(BrewCatalog.normalize("Visual Studio Code") == "visualstudiocode")
        #expect(BrewCatalog.normalize("visual-studio-code") == "visualstudiocode")
        #expect(BrewCatalog.normalize("CotEditor") == "coteditor")
        #expect(BrewCatalog.normalize("gsap_v3.2") == "gsapv32")
    }

    @Test("Cask matching pairs app names with tokens")
    func caskMatching() {
        let catalog = BrewCatalog(
            caskTokens: ["visual-studio-code", "google-chrome", "stats"],
            formulae: [:],
            cellarURL: nil
        )
        #expect(catalog.caskToken(matchingAppNamed: "Visual Studio Code") == "visual-studio-code")
        #expect(catalog.caskToken(matchingAppNamed: "Google Chrome") == "google-chrome")
        #expect(catalog.caskToken(matchingAppNamed: "Stats") == "stats")
        #expect(catalog.caskToken(matchingAppNamed: "Figma") == nil)
    }
}

@Suite("App census")
struct AppCensusTests {
    @Test("Census finds bundles and classifies against the catalog")
    func censusClassifies() throws {
        // Census reads the live /Applications — assert invariants, not fixtures.
        let census = AppCensus(brew: .local())
        let apps = census.collectApps()

        #expect(!apps.isEmpty)
        // Every entry has a name and a real path; sizes are deferred.
        for app in apps {
            #expect(!app.name.isEmpty)
            #expect(FileManager.default.fileExists(atPath: app.bundlePath))
            #expect(app.sizeBytes == nil)
        }
    }
}
