// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "SongNotes",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SongNotes",
            path: "Sources/SongNotes",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("Speech"),
                .linkedFramework("AVFoundation"),
            ]
        )
    ]
)
