// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Pomodorolog",
    platforms: [.macOS(.v14)],
    products: [
        // A droplet is a loadable bundle, so its product is a dynamic library.
        // Do not make it static: the app already carries DroppyKit, and a
        // second copy inside the droplet gives the same type two metadata
        // records, which fails every cast between them.
        .library(name: "Pomodorolog", type: .dynamic, targets: ["Pomodorolog"])
    ],
    dependencies: [
        // Pinned to the DroppyKit that Droppy 16.0.1 carries, so an API newer
        // than the installed app can run is a compile error, not a load failure.
        .package(url: "https://gitlab.com/droppyformac1/droppykit.git", exact: "1.20.1")
    ],
    targets: [
        .target(
            name: "Pomodorolog",
            dependencies: [.product(name: "DroppyKit", package: "droppykit")]
        ),
        .executableTarget(
            name: "PomodorologHarness",
            dependencies: [
                "Pomodorolog",
                .product(name: "DroppyKitHarness", package: "droppykit")
            ]
        ),
        // The session log and the tracker for Droppy's Pomodoro, which need
        // no Droppy to run.
        .testTarget(
            name: "PomodorologTests",
            dependencies: ["Pomodorolog"]
        )
    ]
)
