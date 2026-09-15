import Foundation

@main
struct UpdateChecks {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    static func main() {
        expect(ReleaseVersion.isNewer("v1.1.0", than: "1.0"), "A higher minor release should be newer")
        expect(ReleaseVersion.isNewer("2.0.0", than: "1.9.9"), "A higher major release should be newer")
        expect(!ReleaseVersion.isNewer("v1.0.0", than: "1.0"), "Equivalent versions should not be newer")
        expect(!ReleaseVersion.isNewer("release", than: "1.0.0"), "A tag without a version should be ignored")
        print("Update checks passed")
    }
}
