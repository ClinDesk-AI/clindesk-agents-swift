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
        .library(
            name: "ClinDeskAgentsOpenAI",
            targets: ["ClinDeskAgentsOpenAI"]
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
        .target(
            name: "ClinDeskAgentsOpenAI",
            dependencies: ["ClinDeskAgents"]
        ),
        .executableTarget(
            name: "BasicExample",
            dependencies: [
                "ClinDeskAgents",
                "ClinDeskAgentsOpenAI"
            ],
            path: "Examples/Basic"
        ),
        .testTarget(
            name: "ClinDeskAgentsTests",
            dependencies: [
                "ClinDeskAgents",
                "ClinDeskAgentsOpenAI"
            ]
        )
    ]
)
