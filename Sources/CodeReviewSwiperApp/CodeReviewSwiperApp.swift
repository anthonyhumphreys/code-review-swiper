import SwiftUI

@main
struct CodeReviewSwiperApp: App {
  @StateObject private var session = GitHubSession()
  @StateObject private var reviewStore = ReviewStore()

  var body: some Scene {
    WindowGroup {
      AppRootView()
        .environmentObject(session)
        .environmentObject(reviewStore)
    }
  }
}
