// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "CodeReviewSwiper",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: [
    .executable(name: "CodeReviewSwiper", targets: ["CodeReviewSwiperApp"])
  ],
  targets: [
    .executableTarget(
      name: "CodeReviewSwiperApp",
      path: "Sources/CodeReviewSwiperApp"
    )
  ]
)
