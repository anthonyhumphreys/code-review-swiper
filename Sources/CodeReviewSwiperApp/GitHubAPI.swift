import Foundation

struct GitHubAPI {
  let token: String
  var baseURL = URL(string: "https://api.github.com")!

  func pullRequests(owner: String, repository: String) async throws -> [PullRequest] {
    let url = baseURL.appending(path: "repos/\(owner)/\(repository)/pulls")
    let response: [PullRequestResponse] = try await request(url)
    return response.map { pr in
      PullRequest(
        id: pr.id,
        number: pr.number,
        title: pr.title,
        repositoryFullName: "\(owner)/\(repository)",
        authorLogin: pr.user.login,
        htmlURL: pr.htmlURL
      )
    }
  }

  func changedFiles(for pullRequest: PullRequest) async throws -> [ChangedFile] {
    let parts = pullRequest.repositoryFullName.split(separator: "/")
    guard parts.count == 2 else { throw URLError(.badURL) }
    let url = baseURL.appending(
      path: "repos/\(parts[0])/\(parts[1])/pulls/\(pullRequest.number)/files")
    let response: [ChangedFileResponse] = try await request(url)
    return response.map { file in
      ChangedFile(
        filename: file.filename,
        status: file.status,
        additions: file.additions,
        deletions: file.deletions,
        patch: file.patch ?? "Binary file or diff too large to display.",
        summary: nil,
        verdict: nil
      )
    }
  }

  func leaveReviewComment(_ body: String, on pullRequest: PullRequest, event: String = "COMMENT")
    async throws
  {
    let parts = pullRequest.repositoryFullName.split(separator: "/")
    guard parts.count == 2 else { throw URLError(.badURL) }
    let url = baseURL.appending(
      path: "repos/\(parts[0])/\(parts[1])/pulls/\(pullRequest.number)/reviews")
    let payload = ReviewRequestBody(body: body, event: event)
    let _: EmptyResponse = try await request(url, method: "POST", body: payload)
  }

  private func request<Response: Decodable, Body: Encodable>(
    _ url: URL, method: String = "GET", body: Body? = Optional<Data>.none
  ) async throws -> Response {
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

    if let body {
      request.httpBody = try JSONEncoder.github.encode(body)
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
      throw GitHubAPIError.unexpectedResponse(
        String(data: data, encoding: .utf8) ?? "Unknown API error")
    }

    if Response.self == EmptyResponse.self, data.isEmpty {
      return EmptyResponse() as! Response
    }
    return try JSONDecoder.github.decode(Response.self, from: data)
  }
}

enum GitHubAPIError: Error, LocalizedError {
  case unexpectedResponse(String)

  var errorDescription: String? {
    switch self {
    case .unexpectedResponse(let message): message
    }
  }
}

struct EmptyResponse: Decodable {}

private struct PullRequestResponse: Decodable {
  let id: Int
  let number: Int
  let title: String
  let htmlURL: URL
  let user: User

  enum CodingKeys: String, CodingKey {
    case id, number, title, user
    case htmlURL = "html_url"
  }
}

private struct User: Decodable {
  let login: String
}

private struct ChangedFileResponse: Decodable {
  let filename: String
  let status: String
  let additions: Int
  let deletions: Int
  let patch: String?
}

private struct ReviewRequestBody: Encodable {
  let body: String
  let event: String
}

extension JSONDecoder {
  fileprivate static var github: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
  }
}

extension JSONEncoder {
  fileprivate static var github: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    return encoder
  }
}
