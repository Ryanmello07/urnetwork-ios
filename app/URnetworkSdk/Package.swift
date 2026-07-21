// swift-tools-version:5.3
import PackageDescription

// Points to the local checkout of the forked SDK:
// https://github.com/Ryanmello07/urnetwork-sdk
// Build the XCFramework from that repo before using this package.
let package = Package(
	name: "URnetworkSdk",
	products: [
		.library(
			name: "URnetworkSdk",
			targets: ["URnetworkSdkBinary"]
		),
	],
	targets: [
		.binaryTarget(
			name: "URnetworkSdkBinary",
			path: "../../../urnetwork-sdk/build/apple/URnetworkSdk.xcframework"
		),
		.testTarget(
			name: "URnetworkSdkTests",
			dependencies: ["URnetworkSdkBinary"]
		),
	]
)
