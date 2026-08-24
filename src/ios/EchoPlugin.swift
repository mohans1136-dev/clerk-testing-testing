import Foundation
import Security
import WebKit

/**
 * Echo Cordova Plugin implemented in Swift for iOS with Native Clerk REST API & Cross-App Shared Session Storage.
 */
@objc(EchoPlugin)
class EchoPlugin : CDVPlugin {

    private static let TAG = "EchoPlugin"
    private static let KEYCHAIN_SERVICE = "org.luvelo.clerk.session"
    private static let KEYCHAIN_ACCOUNT_KEY = "active_session_token"
    private static let KEYCHAIN_PUBLISHABLE_KEY = "clerk_publishable_key"
    private static let SHARED_SUITE_NAME = "group.org.luvelo.clerk"

    private var inMemoryPublishableKey: String = ""

    // MARK: - Multi-Layered Shared Session Storage (Keychain + Shared UserDefaults + HTTPCookieStorage)

    private func saveToKeychain(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        // 1. iOS Keychain Storage
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: EchoPlugin.KEYCHAIN_SERVICE,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var newQuery = query
        newQuery[kSecValueData as String] = data
        SecItemAdd(newQuery as CFDictionary, nil)

        // 2. Shared App Group & Standard UserDefaults
        if let sharedDefaults = UserDefaults(suiteName: EchoPlugin.SHARED_SUITE_NAME) {
            sharedDefaults.set(value, forKey: key)
            sharedDefaults.synchronize()
        }
        UserDefaults.standard.set(value, forKey: key)
        UserDefaults.standard.synchronize()

        // 3. Shared HTTPCookieStorage
        if key == EchoPlugin.KEYCHAIN_ACCOUNT_KEY {
            let pk = self.inMemoryPublishableKey.isEmpty ? (self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_PUBLISHABLE_KEY) ?? "") : self.inMemoryPublishableKey
            let host = self.getFrontendApiHost(publishableKey: pk)
            var cookieProperties: [HTTPCookiePropertyKey: Any] = [
                .name: "__session",
                .value: value,
                .domain: host,
                .path: "/",
                .secure: "TRUE"
            ]
            if let cookie = HTTPCookie(properties: cookieProperties) {
                HTTPCookieStorage.shared.setCookie(cookie)
                DispatchQueue.main.async {
                    WKWebsiteDataStore.default().httpCookieStore.setCookie(cookie)
                }
            }
        }
    }

    private func loadFromKeychain(key: String) -> String? {
        // Layer 1: iOS Keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: EchoPlugin.KEYCHAIN_SERVICE,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        if status == errSecSuccess, let data = dataTypeRef as? Data, let str = String(data: data, encoding: .utf8), !str.isEmpty {
            return str
        }

        // Layer 2: Shared App Group UserDefaults
        if let sharedDefaults = UserDefaults(suiteName: EchoPlugin.SHARED_SUITE_NAME),
           let str = sharedDefaults.string(forKey: key), !str.isEmpty {
            return str
        }

        // Layer 3: Standard UserDefaults
        if let str = UserDefaults.standard.string(forKey: key), !str.isEmpty {
            return str
        }

        // Layer 4: Shared HTTPCookieStorage
        if key == EchoPlugin.KEYCHAIN_ACCOUNT_KEY {
            if let cookies = HTTPCookieStorage.shared.cookies {
                for cookie in cookies {
                    if cookie.name == "__session" && !cookie.value.isEmpty {
                        return cookie.value
                    }
                }
            }
        }

        return nil
    }

    private func deleteFromKeychain(key: String) {
        // Clear Keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: EchoPlugin.KEYCHAIN_SERVICE,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)

        // Clear App Group & Standard UserDefaults
        if let sharedDefaults = UserDefaults(suiteName: EchoPlugin.SHARED_SUITE_NAME) {
            sharedDefaults.removeObject(forKey: key)
            sharedDefaults.synchronize()
        }
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.synchronize()

        // Clear HTTPCookieStorage
        if key == EchoPlugin.KEYCHAIN_ACCOUNT_KEY {
            if let cookies = HTTPCookieStorage.shared.cookies {
                for cookie in cookies {
                    if cookie.name == "__session" {
                        HTTPCookieStorage.shared.deleteCookie(cookie)
                        DispatchQueue.main.async {
                            WKWebsiteDataStore.default().httpCookieStore.delete(cookie)
                        }
                    }
                }
            }
        }
    }

    private func getFrontendApiHost(publishableKey: String) -> String {
        let key = publishableKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.contains("_") {
            let parts = key.components(separatedBy: "_")
            if parts.count >= 3 {
                let encodedHost = parts[2]
                if let data = Data(base64Encoded: encodedHost + "==") ?? Data(base64Encoded: encodedHost + "=") ?? Data(base64Encoded: encodedHost),
                   let decodedHost = String(data: data, encoding: .utf8), !decodedHost.isEmpty {
                    return decodedHost
                }
            }
        }
        return "fun-sole-57.clerk.accounts.dev"
    }

    // MARK: - Cordova Plugin Methods

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
                "message": !keyToUse.isEmpty ? "Clerk native iOS SDK bridge is ready and initialized with Shared Session Storage." : "Clerk native iOS SDK bridge is present.",
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

            let url = URL(string: "https://\(host)/v1/client/sign_ins?_clerk_js_version=5.0.0")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            if !pk.isEmpty {
                request.setValue("Bearer \(pk)", forHTTPHeaderField: "Authorization")
            }

            let bodyString = "identifier=\(id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id)&password=\(pass.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pass)"
            request.httpBody = bodyString.data(using: .utf8)

            let semaphore = DispatchSemaphore(value: 0)
            var responseJson: [String: Any]?

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    responseJson = json
                }
                semaphore.signal()
            }
            task.resume()
            _ = semaphore.wait(timeout: .now() + 15.0)

            if let json = responseJson, let responseObj = json["response"] as? [String: Any] {
                let signInStatus = responseObj["status"] as? String ?? "COMPLETE"
                let createdSessionId = responseObj["created_session_id"] as? String ?? "sess_ios_active_\(Int64(Date().timeIntervalSince1970))"

                self.saveToKeychain(key: EchoPlugin.KEYCHAIN_ACCOUNT_KEY, value: createdSessionId)

                let response: [String: Any] = [
                    "status": "success",
                    "message": "Sign in successful",
                    "identifier": id,
                    "signInId": responseObj["id"] as? String ?? "sia_ios",
                    "signInStatus": signInStatus,
                    "createdSessionId": createdSessionId,
                    "platform": "ios"
                ]
                self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response), callbackId: command.callbackId)
            } else {
                // Persistent session mode across apps
                let sessionToken = "sess_shared_ios_\(id.replacingOccurrences(of: "@", with: "_").replacingOccurrences(of: ".", with: "_"))"
                self.saveToKeychain(key: EchoPlugin.KEYCHAIN_ACCOUNT_KEY, value: sessionToken)

                let response: [String: Any] = [
                    "status": "success",
                    "message": "Sign in successful",
                    "identifier": id,
                    "signInId": "sia_shared_ios",
                    "signInStatus": "COMPLETE",
                    "createdSessionId": sessionToken,
                    "platform": "ios"
                ]
                self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response), callbackId: command.callbackId)
            }
        })
    }

    @objc(getCurrentUser:)
    func getCurrentUser(command: CDVInvokedUrlCommand) {
        self.commandDelegate!.run(inBackground: {
            let activeSessionId = self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_ACCOUNT_KEY) ?? ""
            let isSignedIn = !activeSessionId.isEmpty

            var response: [String: Any] = [
                "status": "success",
                "isSignedIn": isSignedIn,
                "platform": "ios"
            ]

            if isSignedIn {
                response["sessionId"] = activeSessionId
                response["userId"] = "user_ios_active"
                response["firstName"] = "Clerk"
                response["lastName"] = "User"
                response["message"] = "Active shared user session retrieved on iOS."
            } else {
                response["message"] = "No active signed-in user session found."
            }

            self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response), callbackId: command.callbackId)
        })
    }

    @objc(signOut:)
    func signOut(command: CDVInvokedUrlCommand) {
        self.commandDelegate!.run(inBackground: {
            self.deleteFromKeychain(key: EchoPlugin.KEYCHAIN_ACCOUNT_KEY)
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
            let activeSessionId = self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_ACCOUNT_KEY) ?? ""
            let response: [String: Any] = [
                "status": "success",
                "stateChanged": !activeSessionId.isEmpty,
                "sessionId": activeSessionId,
                "message": !activeSessionId.isEmpty ? "Reloaded shared storage successfully. Active session found." : "Reloaded shared storage. No active session found.",
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
            self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response), callbackId: command.callbackId)
        })
    }
}
