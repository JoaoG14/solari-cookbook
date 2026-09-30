import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

enum CloudSignInProvider {
    case apple
    case google
}

@MainActor
final class CloudSignIn: NSObject, ASWebAuthenticationPresentationContextProviding,
                         ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var authentication: ASWebAuthenticationSession?
    private var appleAuthorization: ASAuthorizationController?
    private var appleContinuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?
    static var server: URL {
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment["DONY_MOBILE_API_URL"], let url = URL(string: value) { return url }
        #endif
        return URL(string: "http://127.0.0.1:8787")!
    }
    private func randomToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw CompanionFailure("Couldn’t start a secure sign-in.") }
        return Self.base64url(Data(bytes))
    }
    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    private static func sha256Hex(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func signIn() async throws -> (String, CloudAccount) {
        let verifier = try randomToken()
        let state = try randomToken()
        let challenge = Self.base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
        struct Start: Decodable { let url: URL }
        let start: Start = try await request("start", body: ["challenge": challenge, "state": state])
        guard start.url.scheme == Self.server.scheme, start.url.host == Self.server.host else { throw CompanionFailure("Dony returned an invalid sign-in address.") }
        let callback = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(url: start.url, callbackURLScheme: "dony-solari-mobile") { url, error in
                if let error { continuation.resume(throwing: error) }
                else if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: CompanionFailure("Sign-in did not complete.")) }
            }
            session.presentationContextProvider = self
            authentication = session
            if !session.start() { continuation.resume(throwing: CompanionFailure("Couldn’t open sign-in.")) }
        }
        authentication = nil
        guard callback.scheme == "dony-solari-mobile", callback.host == "auth", callback.path == "/callback",
              let parts = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              parts.queryItems?.first(where: { $0.name == "state" })?.value == state,
              let code = parts.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw CompanionFailure("This sign-in does not belong to your request. Try again.")
        }
        struct Exchange: Decodable { let token: String; let user: CloudAccount }
        let exchange: Exchange = try await request("exchange", body: ["code": code, "verifier": verifier, "state": state])
        return (exchange.token, exchange.user)
    }
    func signInWithApple() async throws -> (String, CloudAccount) {
        guard appleContinuation == nil else { throw CompanionFailure("Apple sign-in is already open.") }
        let nonce = try randomToken()
        let appleRequest = ASAuthorizationAppleIDProvider().createRequest()
        appleRequest.requestedScopes = [.fullName, .email]
        appleRequest.nonce = Self.sha256Hex(nonce)
        let credential = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>) in
            appleContinuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [appleRequest])
            controller.delegate = self
            controller.presentationContextProvider = self
            appleAuthorization = controller
            controller.performRequests()
        }
        guard let identityToken = credential.identityToken,
              let token = String(data: identityToken, encoding: .utf8) else {
            throw CompanionFailure("Apple didn’t return a valid sign-in credential.")
        }
        struct AppleName: Encodable { let firstName: String?; let lastName: String? }
        struct AppleUser: Encodable { let name: AppleName?; let email: String? }
        struct AppleInput: Encodable { let identityToken: String; let nonce: String; let user: AppleUser? }
        struct Exchange: Decodable { let token: String; let user: CloudAccount }
        let firstName = credential.fullName?.givenName
        let lastName = credential.fullName?.familyName
        let name = firstName == nil && lastName == nil ? nil : AppleName(firstName: firstName, lastName: lastName)
        let user = name == nil && credential.email == nil
            ? nil
            : AppleUser(name: name, email: credential.email)
        let exchange: Exchange = try await request("apple", body: AppleInput(identityToken: token, nonce: nonce, user: user))
        return (exchange.token, exchange.user)
    }
    private func request<T: Decodable, Body: Encodable>(_ endpoint: String, body: Body) async throws -> T {
        var request = URLRequest(url: Self.server.appending(path: "v1/mobile/auth/\(endpoint)"))
        request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw CompanionFailure("Couldn’t sign in to Dony. Try again.") }
        return try JSONDecoder().decode(T.self, from: data)
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            finishAppleAuthorization(.failure(CompanionFailure("Apple didn’t return a valid sign-in credential.")))
            return
        }
        finishAppleAuthorization(.success(credential))
    }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        finishAppleAuthorization(.failure(error))
    }
    private func finishAppleAuthorization(_ result: Result<ASAuthorizationAppleIDCredential, Error>) {
        let continuation = appleContinuation
        appleContinuation = nil
        appleAuthorization = nil
        continuation?.resume(with: result)
    }
}
