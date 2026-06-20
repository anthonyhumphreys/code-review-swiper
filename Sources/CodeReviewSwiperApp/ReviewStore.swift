import Foundation

#if canImport(FoundationModels)
  import FoundationModels
#endif

@MainActor
final class ReviewStore: ObservableObject {
  @Published var repository = ""
  @Published var pullRequests: [PullRequest] = []
  @Published var selectedPullRequest: PullRequest?
  @Published var files: [ChangedFile] = []
  @Published var finalFeedback: ReviewFeedback?
  @Published var isLoading = false
  @Published var errorMessage: String?

  func loadPullRequests(token: String) async {
    let parts = repository.split(separator: "/")
    guard parts.count == 2 else {
      errorMessage = "Enter a repository as owner/name."
      return
    }

    await perform {
      pullRequests = try await GitHubAPI(token: token).pullRequests(
        owner: String(parts[0]), repository: String(parts[1]))
    }
  }

  func loadFiles(token: String, pullRequest: PullRequest) async {
    selectedPullRequest = pullRequest
    await perform {
      let api = GitHubAPI(token: token)
      let fetchedFiles = try await api.changedFiles(for: pullRequest)
      files = try await summarize(files: fetchedFiles)
      finalFeedback = nil
    }
  }

  func setVerdict(_ verdict: FileVerdict, for file: ChangedFile) {
    guard let index = files.firstIndex(where: { $0.id == file.id }) else { return }
    files[index].verdict = verdict
    if files.allSatisfy({ $0.verdict != nil }) {
      finalFeedback = makeFeedback()
    }
  }

  func submitFeedback(token: String) async {
    guard let selectedPullRequest, let finalFeedback else { return }
    await perform {
      try await GitHubAPI(token: token).leaveReviewComment(
        finalFeedback.commentBody, on: selectedPullRequest)
    }
  }

  private func perform(_ work: () async throws -> Void) async {
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }
    do {
      try await work()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func summarize(files: [ChangedFile]) async throws -> [ChangedFile] {
    var summarized: [ChangedFile] = []
    for var file in files {
      file.summary = try await AppleFoundationModelSummarizer.shared.summarize(file: file)
      summarized.append(file)
    }
    return summarized
  }

  private func makeFeedback() -> ReviewFeedback {
    let accepted = files.filter { $0.verdict == .accepted }.map(\.filename)
    let rejected = files.filter { $0.verdict == .rejected }.map(\.filename)
    let summary =
      "Reviewed \(files.count) files: \(accepted.count) accepted, \(rejected.count) rejected."
    let details = files.map { file in
      "- \(file.verdict == .accepted ? "✅" : "❌") `\(file.filename)`: \(file.summary ?? "No summary available.")"
    }.joined(separator: "\n")
    let concerns =
      rejected.isEmpty
      ? "No file-level concerns were flagged."
      : "Please revisit: \(rejected.map { "`\($0)`" }.joined(separator: ", "))."
    let body = """
      ## Swipe review summary

      \(summary)

      \(details)

      \(concerns)
      """
    return ReviewFeedback(
      approvedFiles: accepted, rejectedFiles: rejected, summary: summary, commentBody: body)
  }
}

struct AppleFoundationModelSummarizer {
  static let shared = AppleFoundationModelSummarizer()

  func summarize(file: ChangedFile) async throws -> String {
    #if canImport(FoundationModels)
      if #available(iOS 26.0, macOS 26.0, *) {
        let session = LanguageModelSession()
        let prompt = """
          Summarize this pull request file diff for a reviewer in two concise sentences.
          File: \(file.filename)
          Status: \(file.status)
          Additions: \(file.additions), deletions: \(file.deletions)
          Diff:\n\(file.patch.prefix(12_000))
          """
        let response = try await session.respond(to: prompt)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
      }
    #endif
    return fallbackSummary(file: file)
  }

  private func fallbackSummary(file: ChangedFile) -> String {
    "\(file.status.capitalized) `\(file.filename)` with +\(file.additions)/-\(file.deletions). Tap to inspect the diff before swiping."
  }
}
