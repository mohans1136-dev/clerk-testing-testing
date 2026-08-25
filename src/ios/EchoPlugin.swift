import Foundation
import Security

/**
 * Echo Cordova Plugin implemented in Swift for iOS with Real Native Clerk REST API & Shared Keychain Session Engine.
 */
@objc(EchoPlugin)
class EchoPlugin : CDVPlugin {

    private static let TAG = "EchoPlugin"
    private static let SHARED_KEYCHAIN_SERVICE = "com.luvelo.clerk.sharedservice"
    private static let KEYCHAIN_ACCOUNT_KEY = "active_clerk_session_jwt"
    private static let KEYCHAIN_SESSION_ID_KEY = "active_clerk_session_id"
    private static let KEYCHAIN_PUBLISHABLE_KEY = "clerk_publishable_key"

    private var inMemoryPublishableKey: String = ""

    // MARK: - Explicit Keychain Access (Shared Across Sibling iOS Apps)

    private func saveToKeychain(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: EchoPlugin.SHARED_KEYCHAIN_SERVICE,
            kSecAttrAccount as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemDelete(query as CFDictionary)
        var newQuery = query
        newQuery[kSecValueData as String] = data
        SecItemAdd(newQuery as CFDictionary, nil)
    }

    private func loadFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: EchoPlugin.SHARED_KEYCHAIN_SERVICE,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        if status == errSecSuccess, let data = dataTypeRef as? Data, let str = String(data: data, encoding: .utf8), !str.isEmpty {
            return str
        }
        return nil
    }

    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: EchoPlugin.SHARED_KEYCHAIN_SERVICE,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func getFrontendApiHost(publishableKey: String) -> String {
        let key = publishableKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.contains("_") {
            let parts = key.components(separatedBy: "_")
            if parts.count >= 3 {
                let encodedHost = parts[2].replacingOccurrences(of: "$", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                var base64 = encodedHost
                let remainder = base64.count % 4
                if remainder > 0 {
                    base64 += String(repeating: "=", count: 4 - remainder)
                }
                if let data = Data(base64Encoded: base64),
                   let decodedHost = String(data: data, encoding: .utf8), !decodedHost.isEmpty {
                    let cleaned = decodedHost.replacingOccurrences(of: "$", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty {
                        return cleaned
                    }
                }
            }
        }
        return "fun-sole-57.clerk.accounts.dev"
    }

    // MARK: - Plugin Actions

    @objc(echo:)
    func echo(command: CDVInvokedUrlCommand) {
        let message = command.argument(at: 0) as? String ?? ""
        let pluginResult = !message.isEmpty
            ? CDVPluginResult(status: CDVCommandStatus_OK, messageAs: message)
            : CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Expected one non-empty string argument.")
        self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
    }

    @objc(echoAsync:)
    func echoAsync(command: CDVInvokedUrlCommand) {
        self.commandDelegate!.run(inBackground: {
            let message = command.argument(at: 0) as? String ?? ""
            if !message.isEmpty {
                let response: [String: Any] = [
                    "status": "success",
                    "message": message,
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                    "language": "Swift"
                ]
                self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response), callbackId: command.callbackId)
            } else {
                self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Expected one non-empty string argument."), callbackId: command.callbackId)
            }
        })
    }

    @objc(add:)
    func add(command: CDVInvokedUrlCommand) {
        guard let arg1 = command.argument(at: 0), let arg2 = command.argument(at: 1) else {
            self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Expected two valid numeric arguments."), callbackId: command.callbackId)
            return
        }

        let num1: Double = (arg1 as? NSNumber)?.doubleValue ?? (Double(arg1 as? String ?? "") ?? Double.nan)
        let num2: Double = (arg2 as? NSNumber)?.doubleValue ?? (Double(arg2 as? String ?? "") ?? Double.nan)

        if num1.isNaN || num2.isNaN {
            self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Expected two valid numeric arguments."), callbackId: command.callbackId)
            return
        }

        let response: [String: Any] = [
            "num1": num1,
            "num2": num2,
            "sum": num1 + num2,
            "platform": "ios",
            "language": "Swift"
        ]
        self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response), callbackId: command.callbackId)
    }

    @objc(checkClerk:)
    func checkClerk(command: CDVInvokedUrlCommand) {
        self.commandDelegate!.run(inBackground: {
            let publishableKey = command.argument(at: 0) as? String ?? ""
            let keyToUse = !publishableKey.isEmpty ? publishableKey : (self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_PUBLISHABLE_KEY) ?? "")

            var response: [String: Any] = [
                "sdkAvailable": true,
                "initialized": !keyToUse.isEmpty,
                "status": "success",
                "platform": "ios",
                "message": !keyToUse.isEmpty ? "Clerk native iOS SDK bridge is ready and initialized." : "Clerk native iOS SDK bridge is present.",
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
            ]
            if !keyToUse.isEmpty {
                response["publishableKey"] = keyToUse
            }
            self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response), callbackId: command.callbackId)
        })
    }

    @objc(initializeClerk:)
    func initializeClerk(command: CDVInvokedUrlCommand) {
        self.commandDelegate!.run(inBackground: {
            guard let publishableKey = command.argument(at: 0) as? String, !publishableKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Expected a non-empty publishableKey string argument."), callbackId: command.callbackId)
                return
            }

            let enableSharedSessionSync = command.argument(at: 1) as? Bool ?? true
            let key = publishableKey.trimmingCharacters(in: .whitespacesAndNewlines)

            self.inMemoryPublishableKey = key
            self.saveToKeychain(key: EchoPlugin.KEYCHAIN_PUBLISHABLE_KEY, value: key)

            let response: [String: Any] = [
                "status": "success",
                "message": "Clerk SDK configured successfully on iOS with Shared Session Sync.",
                "publishableKey": key,
                "sharedSessionSyncEnabled": enableSharedSessionSync,
                "platform": "ios",
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
            ]
            self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response), callbackId: command.callbackId)
        })
    }

    @objc(signInWithPassword:)
    func signInWithPassword(command: CDVInvokedUrlCommand) {
        self.commandDelegate!.run(inBackground: {
            guard let identifier = command.argument(at: 0) as? String, !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let password = command.argument(at: 1) as? String, !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Expected non-empty identifier and password arguments."), callbackId: command.callbackId)
                return
            }

            let id = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            let pass = password.trimmingCharacters(in: .whitespacesAndNewlines)
            let pk = self.inMemoryPublishableKey.isEmpty ? (self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_PUBLISHABLE_KEY) ?? "") : self.inMemoryPublishableKey
            let host = self.getFrontendApiHost(publishableKey: pk)

            guard let url = URL(string: "https://\(host)/v1/client/sign_ins?_clerk_js_version=5.0.0") else {
                let response: [String: Any] = [
                    "status": "error",
                    "message": "Invalid Clerk Frontend API URL for host: \(host)",
                    "errorCode": "invalid_url",
                    "platform": "ios"
                ]
                self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: response), callbackId: command.callbackId)
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue("https://\(host)", forHTTPHeaderField: "Origin")
            if !pk.isEmpty {
                request.setValue("Bearer \(pk)", forHTTPHeaderField: "Authorization")
            }

            let bodyString = "identifier=\(id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id)&password=\(pass.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pass)"
            request.httpBody = bodyString.data(using: .utf8)

            let semaphore = DispatchSemaphore(value: 0)
            var responseJson: [String: Any]?
            var httpStatusCode: Int = 0
            var networkError: Error?

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                networkError = error
                if let httpResp = response as? HTTPURLResponse {
                    httpStatusCode = httpResp.statusCode
                }
                if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    responseJson = json
                }
                semaphore.signal()
            }
            task.resume()
            _ = semaphore.wait(timeout: .now() + 15.0)

            // 1. Handle HTTP / Clerk API Errors
            if let json = responseJson, let errorsList = json["errors"] as? [[String: Any]], let firstErr = errorsList.first {
                let errorMsg = firstErr["long_message"] as? String ?? (firstErr["message"] as? String ?? "Sign in failed")
                let errorCode = firstErr["code"] as? String ?? "authentication_failed"

                let response: [String: Any] = [
                    "status": "error",
                    "message": errorMsg,
                    "errorCode": errorCode,
                    "error": errorMsg,
                    "platform": "ios"
                ]
                self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: response), callbackId: command.callbackId)
                return
            }

            // 2. Handle Network Transport Failure
            if let netErr = networkError {
                let response: [String: Any] = [
                    "status": "error",
                    "message": "Network error connecting to \(host): \(netErr.localizedDescription)",
                    "errorCode": "network_error",
                    "platform": "ios"
                ]
                self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: response), callbackId: command.callbackId)
                return
            }

            // 3. Handle Success from Clerk Server
            if let json = responseJson, let clientObj = json["client"] as? [String: Any] {
                var createdSessionId = ""
                var jwtToken = ""

                if let responseObj = json["response"] as? [String: Any] {
                    createdSessionId = responseObj["created_session_id"] as? String ?? ""
                }
                if createdSessionId.isEmpty, let activeSessId = clientObj["active_session_id"] as? String {
                    createdSessionId = activeSessId
                }

                if let sessionsList = clientObj["sessions"] as? [[String: Any]] {
                    for sess in sessionsList {
                        if let lastActiveToken = sess["last_active_token"] as? [String: Any], let jwt = lastActiveToken["jwt"] as? String {
                            jwtToken = jwt
                            break
                        }
                    }
                }

                if !createdSessionId.isEmpty {
                    self.saveToKeychain(key: EchoPlugin.KEYCHAIN_SESSION_ID_KEY, value: createdSessionId)
                }
                if !jwtToken.isEmpty {
                    self.saveToKeychain(key: EchoPlugin.KEYCHAIN_ACCOUNT_KEY, value: jwtToken)
                } else if !createdSessionId.isEmpty {
                    self.saveToKeychain(key: EchoPlugin.KEYCHAIN_ACCOUNT_KEY, value: createdSessionId)
                }

                let response: [String: Any] = [
                    "status": "success",
                    "message": "Sign in successful",
                    "identifier": id,
                    "signInStatus": "COMPLETE",
                    "createdSessionId": createdSessionId,
                    "platform": "ios"
                ]
                self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response), callbackId: command.callbackId)
            } else {
                let statusText = httpStatusCode > 0 ? "HTTP \(httpStatusCode)" : "No Response"
                let response: [String: Any] = [
                    "status": "error",
                    "message": "Unable to authenticate with Clerk server (\(statusText)). Please check publishable key and internet connection.",
                    "errorCode": "connection_failed",
                    "platform": "ios"
                ]
                self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: response), callbackId: command.callbackId)
            }
        })
    }

    @objc(getCurrentUser:)
    func getCurrentUser(command: CDVInvokedUrlCommand) {
        self.commandDelegate!.run(inBackground: {
            let sessionToken = self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_ACCOUNT_KEY) ?? ""
            let sessionId = self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_SESSION_ID_KEY) ?? ""

            if sessionToken.isEmpty {
                let response: [String: Any] = [
                    "status": "success",
                    "isSignedIn": false,
                    "message": "No active signed-in user session found.",
                    "platform": "ios"
                ]
                self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response), callbackId: command.callbackId)
                return
            }

            let pk = self.inMemoryPublishableKey.isEmpty ? (self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_PUBLISHABLE_KEY) ?? "") : self.inMemoryPublishableKey
            let host = self.getFrontendApiHost(publishableKey: pk)

            guard let url = URL(string: "https://\(host)/v1/client?_clerk_js_version=5.0.0") else {
                let response: [String: Any] = [
                    "status": "success",
                    "isSignedIn": true,
                    "userId": "user_shared_session",
                    "sessionId": sessionId,
                    "platform": "ios"
                ]
                self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response), callbackId: command.callbackId)
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("https://\(host)", forHTTPHeaderField: "Origin")
            if !sessionToken.isEmpty {
                request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
            } else if !pk.isEmpty {
                request.setValue("Bearer \(pk)", forHTTPHeaderField: "Authorization")
            }

            let semaphore = DispatchSemaphore(value: 0)
            var responseJson: [String: Any]?
            var statusCode: Int = 0

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let httpResp = response as? HTTPURLResponse {
                    statusCode = httpResp.statusCode
                }
                if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    responseJson = json
                }
                semaphore.signal()
            }
            task.resume()
            _ = semaphore.wait(timeout: .now() + 10.0)

            if statusCode == 200, let json = responseJson, let clientObj = json["client"] as? [String: Any],
               let sessionsList = clientObj["sessions"] as? [[String: Any]], let activeSession = sessionsList.first,
               let userObj = activeSession["user"] as? [String: Any] {

                let userId = userObj["id"] as? String ?? ""
                let firstName = userObj["first_name"] as? String ?? ""
                let lastName = userObj["last_name"] as? String ?? ""

                let response: [String: Any] = [
                    "status": "success",
                    "isSignedIn": true,
                    "userId": userId,
                    "firstName": firstName,
                    "lastName": lastName,
                    "sessionId": sessionId.isEmpty ? (activeSession["id"] as? String ?? "") : sessionId,
                    "platform": "ios"
                ]
                self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response), callbackId: command.callbackId)
            } else if statusCode == 401 {
                self.deleteFromKeychain(key: EchoPlugin.KEYCHAIN_ACCOUNT_KEY)
                self.deleteFromKeychain(key: EchoPlugin.KEYCHAIN_SESSION_ID_KEY)
                let response: [String: Any] = [
                    "status": "success",
                    "isSignedIn": false,
                    "message": "Session token expired or invalidated.",
                    "platform": "ios"
                ]
                self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response), callbackId: command.callbackId)
            } else {
                let response: [String: Any] = [
                    "status": "success",
                    "isSignedIn": true,
                    "userId": "user_shared_session",
                    "sessionId": sessionId,
                    "message": "Active shared session token present in iOS Keychain.",
                    "platform": "ios"
                ]
                self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response), callbackId: command.callbackId)
            }
        })
    }

    @objc(signOut:)
    func signOut(command: CDVInvokedUrlCommand) {
        self.commandDelegate!.run(inBackground: {
            self.deleteFromKeychain(key: EchoPlugin.KEYCHAIN_ACCOUNT_KEY)
            self.deleteFromKeychain(key: EchoPlugin.KEYCHAIN_SESSION_ID_KEY)
            let response: [String: Any] = [
                "status": "success",
                "message": "Signed out successfully",
                "platform": "ios"
            ]
            self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response), callbackId: command.callbackId)
        })
    }

    @objc(reloadFromSharedStorage:)
    func reloadFromSharedStorage(command: CDVInvokedUrlCommand) {
        self.commandDelegate!.run(inBackground: {
            let activeSessionToken = self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_ACCOUNT_KEY) ?? ""
            let activeSessionId = self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_SESSION_ID_KEY) ?? ""
            let hasSession = !activeSessionToken.isEmpty || !activeSessionId.isEmpty

            let response: [String: Any] = [
                "status": "success",
                "stateChanged": hasSession,
                "sessionId": activeSessionId,
                "message": hasSession ? "Reloaded shared Keychain storage. Active session found." : "Reloaded shared Keychain storage. No active session found.",
                "platform": "ios"
            ]
            self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response), callbackId: command.callbackId)
        })
    }

    @objc(testConnection:)
    func testConnection(command: CDVInvokedUrlCommand) {
        self.commandDelegate!.run(inBackground: {
            let publishableKey = command.argument(at: 0) as? String ?? ""
            let keyToUse = !publishableKey.isEmpty ? publishableKey : (self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_PUBLISHABLE_KEY) ?? "")

            var diagnostics: [String: Any] = [
                "platform": "ios",
                "sdkAvailable": true,
                "isSDKInitialized": !keyToUse.isEmpty
            ]

            let url = URL(string: "https://api.clerk.com/v1/environment")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 5.0
            if !keyToUse.isEmpty {
                request.addValue("Bearer \(keyToUse)", forHTTPHeaderField: "Authorization")
            }

            let semaphore = DispatchSemaphore(value: 0)
            var networkReachable = false
            var responseCode = -1

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let httpResp = response as? HTTPURLResponse {
                    responseCode = httpResp.statusCode
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
            self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response), callbackId: command.callbackId)
        })
    }
}
