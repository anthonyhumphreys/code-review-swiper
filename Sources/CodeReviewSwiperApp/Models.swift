import Foundation

enum FileVerdict: String, Codable, CaseIterable, Identifiable {
  case accepted
  case rejected

  var id: String { rawValue }
}

struct PullRequest: Identifiable, Codable, Equatable {
  let id: Int
  let number: Int
  let title: String
  let repositoryFullName: String
  let authorLogin: String
  let htmlURL: URL
}

struct ChangedFile: Identifiable, Codable, Equatable {
  let filename: String
  let status: String
  let additions: Int
  let deletions: Int
  let patch: String
  var summary: String?
  var verdict: FileVerdict?

  var id: String { filename }
}

struct ReviewFeedback: Codable, Equatable {
  let approvedFiles: [String]
  let rejectedFiles: [String]
  let summary: String
  let commentBody: String
}
