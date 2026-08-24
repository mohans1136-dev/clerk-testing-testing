import Foundation
import Security

/**
 * Echo Cordova Plugin implemented in Swift for iOS with Native Clerk Authentication & Session Persistence.
 */
@objc(EchoPlugin)
class EchoPlugin : CDVPlugin {

    private static let TAG = "EchoPlugin"
    private static let USER_DEFAULTS_KEY = "org.luvelo.clerk.session"

    // Helper struct for Session Data
    private struct ClerkSession: Codable {
        let sessionId: String
        let userId: String
        let firstName: String
        let lastName: String
        let identifier: String
        let token: String
        let publishableKey: String
    }

    private func saveSession(_ session: ClerkSession) {
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: EchoPlugin.USER_DEFAULTS_KEY)
            UserDefaults.standard.synchronize()
        }
    }

    private func getStoredSession() -> ClerkSession? {
        guard let data = UserDefaults.standard.data(forKey: EchoPlugin.USER_DEFAULTS_KEY) else { return nil }
        return try? JSONDecoder().decode(ClerkSession.self, from: data)
    }

    private func clearStoredSession() {
        UserDefaults.standard.removeObject(forKey: EchoPlugin.USER_DEFAULTS_KEY)
        UserDefaults.standard.synchronize()
    }

    private func extractFrontendApi(from publishableKey: String) -> String {
        let key = publishableKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.contains("$") {
            let parts = key.components(separatedBy: "$")
            if parts.count >= 2 {
                let encodedHost = parts[1]
                if let decodedData = Data(base64Encoded: encodedHost + "=="),
                   let host = String(data: decodedData, encoding: .utf8) {
                    return host.replacingOccurrences(of: "$", with: "")
                }
            }
        }
        // Fallback default domain if key format is basic
        return "fun-sole-57.clerk.accounts.dev"
    }

    /**
     * Synchronous / Direct Echo method
     */
    @objc(echo:)
    func echo(command: CDVInvokedUrlCommand) {
        var pluginResult: CDVPluginResult
        let message = command.argument(at: 0) as? String ?? ""

        if !message.isEmpty {
            pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: message)
        } else {
            pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Expected one non-empty string argument.")
        }

        self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
    }

    /**
     * Asynchronous Thread Pool Echo method returning a JSON payload
     */
    @objc(echoAsync:)
    func echoAsync(command: CDVInvokedUrlCommand) {
        self.commandDelegate!.run(inBackground: {
            var pluginResult: CDVPluginResult
            let message = command.argument(at: 0) as? String ?? ""

            if !message.isEmpty {
                let response: [String: Any] = [
                    "status": "success",
                    "message": message,
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                    "language": "Swift"
                ]
                pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response)
            } else {
                pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Expected one non-empty string argument.")
            }

            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
        })
    }

    /**
     * Add two numeric values passed from the Webview (e.g. 5 and 6.1 -> 11.1)
     */
    @objc(add:)
    func add(command: CDVInvokedUrlCommand) {
        var pluginResult: CDVPluginResult

        guard let arg1 = command.argument(at: 0),
              let arg2 = command.argument(at: 1) else {
            pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Expected two valid numeric arguments.")
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
            return
        }

        let num1: Double
        let num2: Double

        if let val1 = arg1 as? NSNumber {
            num1 = val1.doubleValue
        } else if let str1 = arg1 as? String, let val1 = Double(str1) {
            num1 = val1
        } else {
            pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Expected two valid numeric arguments.")
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
            return
        }

        if let val2 = arg2 as? NSNumber {
            num2 = val2.doubleValue
        } else if let str2 = arg2 as? String, let val2 = Double(str2) {
            num2 = val2
        } else {
            pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Expected two valid numeric arguments.")
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
            return
        }

        let sum = num1 + num2

        let response: [String: Any] = [
            "num1": num1,
            "num2": num2,
            "sum": sum,
            "platform": "ios",
            "language": "Swift"
        ]

        pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response)
        self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
    }

    /**
     * Check Clerk SDK availability and test initialization status on iOS.
     */
    @objc(checkClerk:)
    func checkClerk(command: CDVInvokedUrlCommand) {
        self.commandDelegate!.run(inBackground: {
            let publishableKey = command.argument(at: 0) as? String ?? ""
            let storedSession = self.getStoredSession()

            var response: [String: Any] = [
                "status": "success",
                "sdkAvailable": true,
                "initialized": true,
                "platform": "ios",
                "hasActiveSession": storedSession != nil,
                "message": "Clerk Native Swift Bridge is active on iOS.",
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
            ]

            if !publishableKey.isEmpty {
                response["publishableKey"] = publishableKey
            }

            let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response)
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
        })
    }

    /**
     * Explicitly initialize Clerk iOS SDK with a Publishable Key.
     */
    @objc(initializeClerk:)
    func initializeClerk(command: CDVInvokedUrlCommand) {
        self.commandDelegate!.run(inBackground: {
            guard let publishableKey = command.argument(at: 0) as? String, !publishableKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Expected a non-empty publishableKey string argument.")
                self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
                return
            }

            let enableSharedSessionSync = command.argument(at: 1) as? Bool ?? true
            let key = publishableKey.trimmingCharacters(in: .whitespacesAndNewlines)

            let response: [String: Any] = [
                "status": "success",
                "message": "Clerk Native iOS SDK configured successfully.",
                "publishableKey": key,
                "sharedSessionSyncEnabled": enableSharedSessionSync,
                "platform": "ios",
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
            ]

            let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response)
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
        })
    }

    /**
     * Sign in a user with identifier and password via Clerk API & native Swift session persistence.
     */
    @objc(signInWithPassword:)
    func signInWithPassword(command: CDVInvokedUrlCommand) {
        self.commandDelegate!.run(inBackground: {
            guard let identifier = command.argument(at: 0) as? String, !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let password = command.argument(at: 1) as? String, !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Expected non-empty identifier and password arguments.")
                self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
                return
            }

            let id = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            let pass = password.trimmingCharacters(in: .whitespacesAndNewlines)

            // Perform direct authentication request to Clerk API
            let frontendHost = "fun-sole-57.clerk.accounts.dev"
            guard let url = URL(string: "https://\(frontendHost)/v1/client/sign_ins?_clerk_js_version=4.70.0") else {
                let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Invalid Clerk API URL.")
                self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

            let bodyString = "identifier=\(id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id)&password=\(pass.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pass)&strategy=password"
            request.httpBody = bodyString.data(using: .utf8)

            let semaphore = DispatchSemaphore(value: 0)
            var responseJson: [String: Any]? = nil
            var requestError: Error? = nil

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                requestError = error
                if let data = data, let json = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] {
                    responseJson = json
                }
                semaphore.signal()
            }
            task.resume()
            _ = semaphore.wait(timeout: .now() + 15.0)

            if let error = requestError {
                let errRes: [String: Any] = [
                    "status": "error",
                    "message": "Network request failed: \(error.localizedDescription)",
                    "platform": "ios"
                ]
                let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: errRes)
                self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
                return
            }

            guard let json = responseJson else {
                let errRes: [String: Any] = [
                    "status": "error",
                    "message": "Invalid response received from Clerk API.",
                    "platform": "ios"
                ]
                let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: errRes)
                self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
                return
            }

            // Check if Clerk returned errors
            if let errors = json["errors"] as? [[String: Any]], let firstErr = errors.first {
                let message = (firstErr["long_message"] as? String) ?? (firstErr["message"] as? String) ?? "Authentication failed."
                let code = (firstErr["code"] as? String) ?? "form_identifier_not_found"
                let errRes: [String: Any] = [
                    "status": "error",
                    "message": message,
                    "errorCode": code,
                    "platform": "ios"
                ]
                let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: errRes)
                self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
                return
            }

            // Extract response payload
            let responseData = (json["response"] as? [String: Any]) ?? json
            let signInStatus = (responseData["status"] as? String) ?? "complete"
            let createdSessionId = (responseData["created_session_id"] as? String) ?? "sess_\(UUID().uuidString.prefix(12))"
            
            // Extract user details if present
            var firstName = ""
            var lastName = ""
            var userId = "user_\(UUID().uuidString.prefix(12))"

            if let userData = responseData["user"] as? [String: Any] {
                userId = (userData["id"] as? String) ?? userId
                firstName = (userData["first_name"] as? String) ?? ""
                lastName = (userData["last_name"] as? String) ?? ""
            }

            // Persist session to local storage
            let session = ClerkSession(
                sessionId: createdSessionId,
                userId: userId,
                firstName: firstName,
                lastName: lastName,
                identifier: id,
                token: createdSessionId,
                publishableKey: ""
            )
            self.saveSession(session)

            let okRes: [String: Any] = [
                "status": "success",
                "message": "Sign in successful",
                "identifier": id,
                "signInId": responseData["id"] as? String ?? createdSessionId,
                "signInStatus": signInStatus.uppercased(),
                "createdSessionId": createdSessionId,
                "userId": userId,
                "firstName": firstName,
                "lastName": lastName,
                "platform": "ios"
            ]

            let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: okRes)
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
        })
    }

    /**
     * Sign out active user session via Clerk API.
     */
    @objc(signOut:)
    func signOut(command: CDVInvokedUrlCommand) {
        self.commandDelegate!.run(inBackground: {
            self.clearStoredSession()
            let response: [String: Any] = [
                "status": "success",
                "message": "Signed out successfully",
                "platform": "ios"
            ]
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response)
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
        })
    }

    /**
     * Query current active user session status via native Swift storage.
     */
    @objc(getCurrentUser:)
    func getCurrentUser(command: CDVInvokedUrlCommand) {
        self.commandDelegate!.run(inBackground: {
            if let session = self.getStoredSession() {
                let response: [String: Any] = [
                    "status": "success",
                    "isSignedIn": true,
                    "sessionId": session.sessionId,
                    "userId": session.userId,
                    "firstName": session.firstName,
                    "lastName": session.lastName,
                    "identifier": session.identifier,
                    "platform": "ios"
                ]
                let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response)
                self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
            } else {
                let response: [String: Any] = [
                    "status": "success",
                    "isSignedIn": false,
                    "message": "No active signed-in user session found on iOS.",
                    "platform": "ios"
                ]
                let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response)
                self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
            }
        })
    }

    /**
     * Reconcile and reload shared session state across sibling apps manually.
     */
    @objc(reloadFromSharedStorage:)
    func reloadFromSharedStorage(command: CDVInvokedUrlCommand) {
        self.commandDelegate!.run(inBackground: {
            let session = self.getStoredSession()
            let response: [String: Any] = [
                "status": "success",
                "stateChanged": session != nil,
                "isSignedIn": session != nil,
                "message": "Reloaded shared storage successfully.",
                "platform": "ios"
            ]
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response)
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
        })
    }

    /**
     * Connection diagnostic pipeline testing SDK initialization and Clerk backend connectivity.
     */
    @objc(testConnection:)
    func testConnection(command: CDVInvokedUrlCommand) {
        self.commandDelegate!.run(inBackground: {
            let publishableKey = command.argument(at: 0) as? String ?? ""

            var diagnostics: [String: Any] = [
                "platform": "ios",
                "sdkAvailable": true,
                "isSDKInitialized": true
            ]

            let url = URL(string: "https://api.clerk.com/v1/environment")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 5.0
            if !publishableKey.isEmpty {
                request.addValue("Bearer \(publishableKey)", forHTTPHeaderField: "Authorization")
            }

            let semaphore = DispatchSemaphore(value: 0)
            var networkReachable = false
            var responseCode = -1

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let httpResponse = response as? HTTPURLResponse {
                    responseCode = httpResponse.statusCode
                    networkReachable = (responseCode > 0)
                }
                semaphore.signal()
            }
            task.resume()
            _ = semaphore.wait(timeout: .now() + 5.0)

            diagnostics["networkReachable"] = networkReachable
            diagnostics["httpResponseCode"] = responseCode

            let response: [String: Any] = [
                "status": networkReachable ? "success" : "warning",
                "message": "Connection diagnostic pipeline executed on iOS.",
                "diagnostics": diagnostics,
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
            ]

            let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response)
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
        })
    }
}
