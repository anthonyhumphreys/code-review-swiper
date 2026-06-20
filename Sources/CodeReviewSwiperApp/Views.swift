import SwiftUI

struct AppRootView: View {
  @EnvironmentObject private var session: GitHubSession

  var body: some View {
    NavigationStack {
      if session.isSignedIn {
        PullRequestPickerView()
      } else {
        SignInView()
      }
    }
  }
}

struct SignInView: View {
  @EnvironmentObject private var session: GitHubSession
  @State private var token = ""

  var body: some View {
    VStack(spacing: 24) {
      Image(systemName: "rectangle.stack.fill.badge.person.crop")
        .font(.system(size: 72))
        .foregroundStyle(.purple.gradient)
      Text("Code Review Swiper")
        .font(.largeTitle.bold())
      Text(
        "Sign in with GitHub, review each changed file as a swipe card, then post a concise PR review summary."
      )
      .font(.body)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)

      Button("Sign in with GitHub") {
        Task { await session.signIn() }
      }
      .buttonStyle(.borderedProminent)

      VStack(alignment: .leading) {
        Text("Or paste a GitHub token for local development")
          .font(.caption)
          .foregroundStyle(.secondary)
        SecureField("ghp_…", text: $token)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        Button("Use token") { session.usePersonalAccessToken(token) }
          .disabled(token.isEmpty)
      }
      .padding()
      .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))

      if let error = session.errorMessage {
        Text(error).foregroundStyle(.red)
      }
    }
    .padding(28)
  }
}

struct PullRequestPickerView: View {
  @EnvironmentObject private var session: GitHubSession
  @EnvironmentObject private var store: ReviewStore

  var body: some View {
    VStack(spacing: 16) {
      HStack {
        TextField("owner/repository", text: $store.repository)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .textFieldStyle(.roundedBorder)
        Button("Load") { loadPRs() }
          .buttonStyle(.borderedProminent)
      }

      if store.isLoading { ProgressView() }

      List(store.pullRequests) { pullRequest in
        NavigationLink(value: pullRequest) {
          VStack(alignment: .leading, spacing: 4) {
            Text("#\(pullRequest.number) \(pullRequest.title)")
              .font(.headline)
            Text("\(pullRequest.repositoryFullName) by @\(pullRequest.authorLogin)")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
      .listStyle(.plain)

      if let error = store.errorMessage {
        Text(error).foregroundStyle(.red)
      }
    }
    .padding()
    .navigationTitle("Pull requests")
    .toolbar {
      Button("Sign out") { session.signOut() }
    }
    .navigationDestination(for: PullRequest.self) { pullRequest in
      SwipeReviewView(pullRequest: pullRequest)
    }
  }

  private func loadPRs() {
    guard let token = session.accessToken else { return }
    Task { await store.loadPullRequests(token: token) }
  }
}

struct SwipeReviewView: View {
  @EnvironmentObject private var session: GitHubSession
  @EnvironmentObject private var store: ReviewStore
  let pullRequest: PullRequest

  private var remainingFiles: [ChangedFile] {
    store.files.filter { $0.verdict == nil }
  }

  var body: some View {
    VStack(spacing: 18) {
      if store.isLoading {
        ProgressView("Preparing AI summaries…")
      } else if let feedback = store.finalFeedback {
        ReviewCompleteView(feedback: feedback)
      } else if let file = remainingFiles.first {
        Text("\(remainingFiles.count) files left")
          .font(.headline)
          .foregroundStyle(.secondary)
        FileSwipeCard(file: file) { verdict in
          withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            store.setVerdict(verdict, for: file)
          }
        }
      } else {
        ContentUnavailableView("No changed files", systemImage: "doc.text.magnifyingglass")
      }

      if let error = store.errorMessage {
        Text(error).foregroundStyle(.red)
      }
    }
    .padding()
    .navigationTitle("Swipe review")
    .navigationBarTitleDisplayMode(.inline)
    .task {
      guard store.selectedPullRequest != pullRequest, let token = session.accessToken else {
        return
      }
      await store.loadFiles(token: token, pullRequest: pullRequest)
    }
  }
}

struct FileSwipeCard: View {
  let file: ChangedFile
  let onVerdict: (FileVerdict) -> Void

  @State private var isFlipped = false
  @State private var dragOffset: CGSize = .zero

  var body: some View {
    VStack(spacing: 18) {
      card
        .rotationEffect(.degrees(Double(dragOffset.width / 18)))
        .offset(dragOffset)
        .gesture(
          DragGesture()
            .onChanged { dragOffset = $0.translation }
            .onEnded { value in
              if value.translation.width > 120 {
                onVerdict(.accepted)
              } else if value.translation.width < -120 {
                onVerdict(.rejected)
              }
              dragOffset = .zero
            }
        )
        .onTapGesture { withAnimation(.bouncy) { isFlipped.toggle() } }

      HStack(spacing: 24) {
        Button {
          onVerdict(.rejected)
        } label: {
          Label("Reject", systemImage: "xmark.circle.fill")
        }
        .buttonStyle(.bordered)
        .tint(.red)

        Button {
          onVerdict(.accepted)
        } label: {
          Label("Accept", systemImage: "checkmark.circle.fill")
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
      }
    }
  }

  private var card: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 28)
        .fill(.background)
        .shadow(color: .black.opacity(0.18), radius: 22, y: 14)
      if isFlipped {
        DiffView(file: file)
          .transition(.opacity.combined(with: .scale))
      } else {
        SummaryView(file: file)
          .transition(.opacity.combined(with: .scale))
      }
    }
    .frame(maxWidth: 520, minHeight: 520)
    .overlay(alignment: .topTrailing) {
      Text(isFlipped ? "DIFF" : "SUMMARY")
        .font(.caption.bold())
        .padding(8)
        .background(.purple.opacity(0.15), in: Capsule())
        .padding()
    }
  }
}

struct SummaryView: View {
  let file: ChangedFile

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(file.filename)
        .font(.title2.bold())
        .textSelection(.enabled)
      HStack {
        Label("+\(file.additions)", systemImage: "plus")
          .foregroundStyle(.green)
        Label("-\(file.deletions)", systemImage: "minus")
          .foregroundStyle(.red)
        Text(file.status.capitalized)
          .padding(.horizontal, 10)
          .padding(.vertical, 4)
          .background(.secondary.opacity(0.15), in: Capsule())
      }
      Text(file.summary ?? "Generating summary…")
        .font(.title3)
      Spacer()
      Text("Tap to flip. Swipe right to accept, left to reject.")
        .font(.callout)
        .foregroundStyle(.secondary)
    }
    .padding(28)
  }
}

struct DiffView: View {
  let file: ChangedFile

  var body: some View {
    ScrollView {
      Text(file.patch)
        .font(.system(.caption, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .padding()
    }
    .background(.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 22))
    .padding(20)
  }
}

struct ReviewCompleteView: View {
  @EnvironmentObject private var session: GitHubSession
  @EnvironmentObject private var store: ReviewStore
  let feedback: ReviewFeedback

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label("Review ready", systemImage: "sparkles")
        .font(.largeTitle.bold())
      Text(feedback.summary)
        .font(.headline)
      ScrollView {
        Text(feedback.commentBody)
          .frame(maxWidth: .infinity, alignment: .leading)
          .textSelection(.enabled)
          .padding()
      }
      .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
      Button("Post feedback to GitHub") {
        guard let token = session.accessToken else { return }
        Task { await store.submitFeedback(token: token) }
      }
      .buttonStyle(.borderedProminent)
    }
    .padding()
  }
}
