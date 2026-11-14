// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AuTutor",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AuTutor", targets: ["AuTutor"])],
    targets: [
        .target(name: "StudyCore"),
        .executableTarget(name: "AuTutor", dependencies: ["StudyCore"]),
        .testTarget(name: "StudyCoreTests", dependencies: ["StudyCore"])
    ]
)
