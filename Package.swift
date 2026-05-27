// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "clindesk-agents",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(
            name: "ClinDeskAgents",
            targets: ["ClinDeskAgents"]
        ),
        .executable(
            name: "BasicExample",
            targets: ["BasicExample"]
        )
    ],
    targets: [
        .target(
            name: "ClinDeskAgents"
        ),
        .executableTarget(
            name: "BasicExample",
            dependencies: [
                "ClinDeskAgents"
            ],
            path: "Examples/Basic"
        ),
        .testTarget(
            name: "ClinDeskAgentsTests",
            dependencies: [
                "ClinDeskAgents"
            ]
        )
    ]
)
