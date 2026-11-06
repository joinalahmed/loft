// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Isla",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Isla",
            path: "Sources/Isla",
            swiftSettings: [
                .unsafeFlags(["-Onone"], .when(configuration: .debug))
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Combine"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("IOKit"),
                .linkedFramework("EventKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("Network"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("CoreImage"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("Vision"),
                .linkedFramework("CoreMediaIO"),
            ]
        )
    ]
)
