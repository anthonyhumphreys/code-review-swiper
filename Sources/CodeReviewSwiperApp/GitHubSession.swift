import Foundation
import SwiftUI

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

@MainActor
final class GitHubSession: ObservableObject {
  @Published private(set) var accessToken: String?
  @Published var errorMessage: String?

  private let tokenStorageKey = "github.accessToken"

  init() {
    accessToken = UserDefaults.standard.string(forKey: tokenStorageKey)
  }

  var isSignedIn: Bool { accessToken != nil }

  func signIn() async {
    guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GITHUB_CLIENT_ID") as? String,
      !clientID.isEmpty,
      clientID != "YOUR_GITHUB_CLIENT_ID"
    else {
      errorMessage = "Add a GitHub OAuth client id to GITHUB_CLIENT_ID before signing in."
      return
    }

    do {
      let deviceCode = try await GitHubOAuth.deviceCode(clientID: clientID)
      openVerificationPage(deviceCode.verificationURI)
      accessToken = try await GitHubOAuth.pollForAccessToken(
        clientID: clientID, deviceCode: deviceCode.deviceCode, interval: deviceCode.interval)
      UserDefaults.standard.set(accessToken, forKey: tokenStorageKey)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func openVerificationPage(_ url: URL) {
    #if os(iOS)
      UIApplication.shared.open(url)
    #elseif os(macOS)
      NSWorkspace.shared.open(url)
    #endif
  }

  func usePersonalAccessToken(_ token: String) {
    let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    accessToken = trimmed
    UserDefaults.standard.set(trimmed, forKey: tokenStorageKey)
  }

  func signOut() {
    accessToken = nil
    UserDefaults.standard.removeObject(forKey: tokenStorageKey)
  }
}

private enum GitHubOAuth {
  static func deviceCode(clientID: String) async throws -> DeviceCodeResponse {
    var request = URLRequest(url: URL(string: "https://github.com/login/device/code")!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.httpBody = try JSONEncoder.githubOAuth.encode(
      DeviceCodeRequest(clientID: clientID, scope: "repo"))

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
      throw GitHubOAuthError.unexpectedResponse(
        String(data: data, encoding: .utf8) ?? "Unknown OAuth error")
    }
    return try JSONDecoder.githubOAuth.decode(DeviceCodeResponse.self, from: data)
  }

  static func pollForAccessToken(clientID: String, deviceCode: String, interval: Int) async throws
    -> String
  {
    var pollInterval = max(interval, 5)
    while true {
      try await Task.sleep(for: .seconds(pollInterval))
      let tokenResponse = try await accessToken(clientID: clientID, deviceCode: deviceCode)
      if let token = tokenResponse.accessToken {
        return token
      }

      switch tokenResponse.error {
      case "authorization_pending":
        continue
      case "slow_down":
        pollInterval += 5
      case let error?:
        throw GitHubOAuthError.unexpectedResponse(tokenResponse.errorDescription ?? error)
      case nil:
        throw GitHubOAuthError.unexpectedResponse("GitHub did not return an access token.")
      }
    }
  }

  private static func accessToken(clientID: String, deviceCode: String) async throws
    -> TokenResponse
  {
    var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.httpBody = try JSONEncoder.githubOAuth.encode(
      TokenRequest(
        clientID: clientID,
        deviceCode: deviceCode,
        grantType: "urn:ietf:params:oauth:grant-type:device_code"))

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
      throw GitHubOAuthError.unexpectedResponse(
        String(data: data, encoding: .utf8) ?? "Unknown OAuth error")
    }
    return try JSONDecoder.githubOAuth.decode(TokenResponse.self, from: data)
  }
}

private enum GitHubOAuthError: Error, LocalizedError {
  case unexpectedResponse(String)

  var errorDescription: String? {
    switch self {
    case .unexpectedResponse(let message): message
    }
  }
}

private struct DeviceCodeRequest: Encodable {
  let clientID: String
  let scope: String
}

private struct TokenRequest: Encodable {
  let clientID: String
  let deviceCode: String
  let grantType: String
}

private struct DeviceCodeResponse: Decodable {
  let deviceCode: String
  let userCode: String
  let verificationURI: URL
  let expiresIn: Int
  let interval: Int
}

private struct TokenResponse: Decodable {
  let accessToken: String?
  let error: String?
  let errorDescription: String?
}

extension JSONDecoder {
  fileprivate static var githubOAuth: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
  }
}

extension JSONEncoder {
  fileprivate static var githubOAuth: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    return encoder
  }
}
