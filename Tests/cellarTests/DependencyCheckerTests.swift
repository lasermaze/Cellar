import Testing
@testable import cellar

// MARK: - Tests

@Suite("DependencyChecker Tests")
struct DependencyCheckerTests {

    // MARK: detectHomebrew — ARM path

    @Test("detectHomebrew returns ARM path when only ARM brew exists")
    func detectHomebrewARM() {
        let sut = DependencyChecker(existingPaths: ["/opt/homebrew/bin/brew"])

        let result = sut.detectHomebrew()

        #expect(result?.path == "/opt/homebrew/bin/brew")
    }

    @Test("detectHomebrew returns Intel path when only Intel brew exists")
    func detectHomebrewIntel() {
        let sut = DependencyChecker(existingPaths: ["/usr/local/bin/brew"])

        let result = sut.detectHomebrew()

        #expect(result?.path == "/usr/local/bin/brew")
    }

    @Test("detectHomebrew prefers ARM path over Intel when both exist")
    func detectHomebrewArmPriorityOverIntel() {
        let sut = DependencyChecker(existingPaths: [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew",
        ])

        let result = sut.detectHomebrew()

        // ARM must be checked first
        #expect(result?.path == "/opt/homebrew/bin/brew")
    }

    @Test("detectHomebrew returns nil when no brew found")
    func detectHomebrewNil() {
        let sut = DependencyChecker(existingPaths: [])

        let result = sut.detectHomebrew()

        #expect(result == nil)
    }

    // MARK: detectWine — binary resolution from brew prefix

    @Test("detectWine returns wine64 when wine64 binary exists in brew bin dir")
    func detectWineWine64() {
        let sut = DependencyChecker(existingPaths: [
            "/opt/homebrew/bin/brew",
            "/opt/homebrew/bin/wine64",
        ])
        let brewPrefix = sut.detectHomebrew()!

        let result = sut.detectWine(brewPrefix: brewPrefix)

        #expect(result?.path == "/opt/homebrew/bin/wine64")
    }

    @Test("detectWine falls back to wine when only wine binary exists")
    func detectWineFallback() {
        let sut = DependencyChecker(existingPaths: [
            "/opt/homebrew/bin/brew",
            "/opt/homebrew/bin/wine",
        ])
        let brewPrefix = sut.detectHomebrew()!

        let result = sut.detectWine(brewPrefix: brewPrefix)

        #expect(result?.path == "/opt/homebrew/bin/wine")
    }

    @Test("detectWine prefers wine64 over wine when both exist")
    func detectWinePreferWine64() {
        let sut = DependencyChecker(existingPaths: [
            "/opt/homebrew/bin/brew",
            "/opt/homebrew/bin/wine64",
            "/opt/homebrew/bin/wine",
        ])
        let brewPrefix = sut.detectHomebrew()!

        let result = sut.detectWine(brewPrefix: brewPrefix)

        #expect(result?.path == "/opt/homebrew/bin/wine64")
    }

    @Test("detectWine returns nil when no wine binary found")
    func detectWineNil() {
        let sut = DependencyChecker(existingPaths: ["/opt/homebrew/bin/brew"])
        let brewPrefix = sut.detectHomebrew()!

        let result = sut.detectWine(brewPrefix: brewPrefix)

        #expect(result == nil)
    }

    @Test("detectWine derives bin dir from Intel brew prefix correctly")
    func detectWineIntelPrefix() {
        let sut = DependencyChecker(existingPaths: [
            "/usr/local/bin/brew",
            "/usr/local/bin/wine64",
        ])
        let brewPrefix = sut.detectHomebrew()!

        let result = sut.detectWine(brewPrefix: brewPrefix)

        #expect(result?.path == "/usr/local/bin/wine64")
    }

    // MARK: DependencyStatus.allRequired computed property

    @Test("allRequired is true when homebrew, wine, and winetricks are all present")
    func allRequiredTrue() {
        let sut = DependencyChecker(existingPaths: [
            "/opt/homebrew/bin/brew",
            "/opt/homebrew/bin/wine64",
            "/opt/homebrew/bin/winetricks",
        ])
        let status = sut.checkAll()
        #expect(status.allRequired == true)
    }

    @Test("allRequired is false when homebrew is absent")
    func allRequiredFalseNoHomebrew() {
        let sut = DependencyChecker(existingPaths: [])
        let status = sut.checkAll()
        #expect(status.allRequired == false)
    }

    @Test("allRequired is false when wine is absent but homebrew present")
    func allRequiredFalseNoWine() {
        let sut = DependencyChecker(existingPaths: ["/opt/homebrew/bin/brew"])
        let status = sut.checkAll()
        #expect(status.allRequired == false)
    }

    @Test("allRequired is false when both homebrew and wine are absent")
    func allRequiredFalseBothNil() {
        let sut = DependencyChecker(existingPaths: [])
        let status = sut.checkAll()
        #expect(status.homebrew == nil)
        #expect(status.wine == nil)
        #expect(status.allRequired == false)
    }

    // MARK: detectGPTK

    @Test("detectGPTK returns true when Intel GPTK path exists")
    func detectGPTKIntel() {
        let sut = DependencyChecker(existingPaths: ["/usr/local/bin/gameportingtoolkit"])
        #expect(sut.detectGPTK() == true)
    }

    @Test("detectGPTK returns true when Homebrew GPTK path exists")
    func detectGPTKHomebrew() {
        let sut = DependencyChecker(existingPaths: ["/opt/homebrew/bin/gameportingtoolkit"])
        #expect(sut.detectGPTK() == true)
    }

    @Test("detectGPTK returns false when not installed")
    func detectGPTKFalse() {
        let sut = DependencyChecker(existingPaths: [])
        #expect(sut.detectGPTK() == false)
    }
}
