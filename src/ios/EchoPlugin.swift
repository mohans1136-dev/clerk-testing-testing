import Foundation
import Security
import WebKit
import AuthenticationServices

/**
 * Echo Cordova Plugin implemented in Swift for iOS with Native Clerk REST API & Shared Keychain Session Engine.
 */
@objc(EchoPlugin)
class EchoPlugin : CDVPlugin {

    private static let TAG = "EchoPlugin"
    private static let SHARED_KEYCHAIN_SERVICE = "com.luvelo.clerk.sharedservice"
    private static let KEYCHAIN_ACCOUNT_KEY = "active_clerk_session_jwt"
    private static let KEYCHAIN_SESSION_ID_KEY = "active_clerk_session_id"
    private static let KEYCHAIN_PUBLISHABLE_KEY = "clerk_publishable_key"
    private static let KEYCHAIN_DEV_BROWSER_JWT_KEY = "clerk_dev_browser_jwt"
    private static let KEYCHAIN_USER_ID_KEY = "active_clerk_user_id"
    private static let KEYCHAIN_FIRST_NAME_KEY = "active_clerk_first_name"
    private static let KEYCHAIN_LAST_NAME_KEY = "active_clerk_last_name"
    private static let KEYCHAIN_EMAIL_KEY = "active_clerk_email"

    private var inMemoryPublishableKey: String = ""
    private var authSession: ASWebAuthenticationSession?

    // MARK: - Explicit Keychain & Cookie Cleaning

    private func purgeAllClerkCookies() {
        self.deleteFromKeychain(key: EchoPlugin.KEYCHAIN_DEV_BROWSER_JWT_KEY)
        if let cookies = HTTPCookieStorage.shared.cookies {
            for cookie in cookies {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
        DispatchQueue.main.async {
            let dataStore = WKWebsiteDataStore.default()
            let types = WKWebsiteDataStore.allWebsiteDataTypes()
            dataStore.removeData(ofTypes: types, modifiedSince: Date(timeIntervalSince1970: 0), completionHandler: {})
        }
    }

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

    private func extractAndSaveDevBrowserJwt(response: URLResponse?) {
        guard let httpResp = response as? HTTPURLResponse else { return }
        if let dbJwt = httpResp.value(forHTTPHeaderField: "Clerk-Db-Jwt") ?? httpResp.value(forHTTPHeaderField: "clerk-db-jwt"), !dbJwt.isEmpty {
            self.saveToKeychain(key: EchoPlugin.KEYCHAIN_DEV_BROWSER_JWT_KEY, value: dbJwt)
            return
        }
        if let allHeaders = httpResp.allHeaderFields as? [String: String] {
            for (headerKey, headerVal) in allHeaders {
                if headerKey.lowercased() == "clerk-db-jwt" && !headerVal.isEmpty {
                    self.saveToKeychain(key: EchoPlugin.KEYCHAIN_DEV_BROWSER_JWT_KEY, value: headerVal)
                    return
                }
                if headerKey.lowercased() == "set-cookie" && headerVal.contains("__clerk_db_jwt=") {
                    let parts = headerVal.components(separatedBy: "__clerk_db_jwt=")
                    if parts.count > 1 {
                        let cookieVal = parts[1].components(separatedBy: ";").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        if !cookieVal.isEmpty {
                            self.saveToKeychain(key: EchoPlugin.KEYCHAIN_DEV_BROWSER_JWT_KEY, value: cookieVal)
                            return
                        }
                    }
                }
            }
        }
    }

    private func getFrontendApiHost(publishableKey: String) -> String? {
        let key = publishableKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.contains("_") else { return nil }

        let parts = key.components(separatedBy: "_")
        guard parts.count >= 3 else { return nil }

        let rawBase64 = parts.dropFirst(2).joined(separator: "_")
            .replacingOccurrences(of: "$", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var base64 = rawBase64
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        if let data = Data(base64Encoded: base64),
           let decodedHost = String(data: data, encoding: .utf8) {
            let cleaned = decodedHost.replacingOccurrences(of: "$", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                return cleaned
            }
        }

        return nil
    }

    private func getAccountPortalHost(publishableKey: String) -> String? {
        guard let fapiHost = self.getFrontendApiHost(publishableKey: publishableKey) else { return nil }
        if fapiHost.hasSuffix(".clerk.accounts.dev") {
            return fapiHost.replacingOccurrences(of: ".clerk.accounts.dev", with: ".accounts.dev")
        }
        return fapiHost
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

    private func executeSignIn(id: String, pass: String, pk: String, host: String, isRetry: Bool, completion: @escaping ([String: Any]?, Int, Error?) -> Void) {
        guard var urlComponents = URLComponents(string: "https://\(host)/v1/client/sign_ins") else {
            completion(["status": "error", "message": "Invalid Clerk Frontend API URL for host: \(host)", "errorCode": "invalid_url"], 0, nil)
            return
        }

        var queryItems = [URLQueryItem(name: "_clerk_js_version", value: "5.0.0")]
        if !isRetry, let dbJwt = self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_DEV_BROWSER_JWT_KEY), !dbJwt.isEmpty {
            queryItems.append(URLQueryItem(name: "_clerk_db_jwt", value: dbJwt))
        }
        urlComponents.queryItems = queryItems

        guard let url = urlComponents.url else {
            completion(["status": "error", "message": "Failed to construct URL"], 0, nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        if !pk.isEmpty {
            request.setValue("Bearer \(pk)", forHTTPHeaderField: "Authorization")
        }
        if !isRetry, let dbJwt = self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_DEV_BROWSER_JWT_KEY), !dbJwt.isEmpty {
            request.setValue(dbJwt, forHTTPHeaderField: "Clerk-Db-Jwt")
        }

        let encodedId = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id
        let encodedPass = pass.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pass
        let bodyString = "strategy=password&identifier=\(encodedId)&password=\(encodedPass)"
        request.httpBody = bodyString.data(using: .utf8)

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            self.extractAndSaveDevBrowserJwt(response: response)
            var statusCode = 0
            if let httpResp = response as? HTTPURLResponse {
                statusCode = httpResp.statusCode
            }
            var responseJson: [String: Any]?
            if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                responseJson = json
            }
            completion(responseJson, statusCode, error)
        }
        task.resume()
    }

    private func processSignInResponse(json: [String: Any]?, statusCode: Int, netErr: Error?, host: String, id: String, command: CDVInvokedUrlCommand) {
        if let json = json, let errorsList = json["errors"] as? [[String: Any]], let firstErr = errorsList.first {
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

        if let netErr = netErr {
            let response: [String: Any] = [
                "status": "error",
                "message": "Network error connecting to \(host): \(netErr.localizedDescription)",
                "errorCode": "network_error",
                "platform": "ios"
            ]
            self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: response), callbackId: command.callbackId)
            return
        }

        if let json = json, let clientObj = json["client"] as? [String: Any] {
            var createdSessionId = ""
            var jwtToken = ""
            var userId = ""
            var firstName = ""
            var lastName = ""
            var userEmail = ""

            if let responseObj = json["response"] as? [String: Any] {
                createdSessionId = responseObj["created_session_id"] as? String ?? ""
            }
            if createdSessionId.isEmpty, let activeSessId = clientObj["active_session_id"] as? String {
                createdSessionId = activeSessId
            }

            if let sessionsList = clientObj["sessions"] as? [[String: Any]] {
                let activeSess = sessionsList.first(where: { ($0["id"] as? String) == createdSessionId }) ?? sessionsList.first
                if let sess = activeSess {
                    if let lastActiveToken = sess["last_active_token"] as? [String: Any], let jwt = lastActiveToken["jwt"] as? String {
                        jwtToken = jwt
                    }
                    if let userObj = sess["user"] as? [String: Any] {
                        userId = userObj["id"] as? String ?? ""
                        firstName = userObj["first_name"] as? String ?? ""
                        lastName = userObj["last_name"] as? String ?? ""
                        if let emailList = userObj["email_addresses"] as? [[String: Any]], let firstEmail = emailList.first {
                            userEmail = firstEmail["email_address"] as? String ?? ""
                        }
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
            if !userId.isEmpty {
                self.saveToKeychain(key: EchoPlugin.KEYCHAIN_USER_ID_KEY, value: userId)
            }
            if !firstName.isEmpty {
                self.saveToKeychain(key: EchoPlugin.KEYCHAIN_FIRST_NAME_KEY, value: firstName)
            }
            if !lastName.isEmpty {
                self.saveToKeychain(key: EchoPlugin.KEYCHAIN_LAST_NAME_KEY, value: lastName)
            }
            if !userEmail.isEmpty {
                self.saveToKeychain(key: EchoPlugin.KEYCHAIN_EMAIL_KEY, value: userEmail)
            }

            let response: [String: Any] = [
                "status": "success",
                "message": "Sign in successful",
                "identifier": id,
                "signInStatus": "COMPLETE",
                "createdSessionId": createdSessionId,
                "userId": userId,
                "firstName": firstName,
                "lastName": lastName,
                "platform": "ios"
            ]
            self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response), callbackId: command.callbackId)
        } else {
            let statusText = statusCode > 0 ? "HTTP \(statusCode)" : "No Response"
            let response: [String: Any] = [
                "status": "error",
                "message": "Unable to authenticate with Clerk server (\(statusText)). Please check publishable key and internet connection.",
                "errorCode": "connection_failed",
                "platform": "ios"
            ]
            self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: response), callbackId: command.callbackId)
        }
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
            guard let host = self.getFrontendApiHost(publishableKey: pk), !host.isEmpty else {
                let response: [String: Any] = [
                    "status": "error",
                    "message": "Clerk publishable key is missing or invalid. Please call initializeClerk(publishableKey) first.",
                    "errorCode": "clerk_not_initialized",
                    "platform": "ios"
                ]
                self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: response), callbackId: command.callbackId)
                return
            }

            self.executeSignIn(id: id, pass: pass, pk: pk, host: host, isRetry: false) { json, statusCode, netErr in
                // Check if dev_browser_unauthenticated occurred
                if let json = json, let errorsList = json["errors"] as? [[String: Any]], let firstErr = errorsList.first {
                    let errorCode = firstErr["code"] as? String ?? ""
                    if errorCode == "dev_browser_unauthenticated" {
                        // Purge all stale Clerk cookies and dev browser token, then auto-retry with clean state
                        self.purgeAllClerkCookies()
                        self.executeSignIn(id: id, pass: pass, pk: pk, host: host, isRetry: true) { retryJson, retryStatus, retryErr in
                            self.processSignInResponse(json: retryJson, statusCode: retryStatus, netErr: retryErr, host: host, id: id, command: command)
                        }
                        return
                    }
                }

                self.processSignInResponse(json: json, statusCode: statusCode, netErr: netErr, host: host, id: id, command: command)
            }
        })
    }

    @objc(getCurrentUser:)
    func getCurrentUser(command: CDVInvokedUrlCommand) {
        self.commandDelegate!.run(inBackground: {
            let sessionId = self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_SESSION_ID_KEY) ?? ""
            let userId = self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_USER_ID_KEY) ?? ""
            let firstName = self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_FIRST_NAME_KEY) ?? ""
            let lastName = self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_LAST_NAME_KEY) ?? ""
            let email = self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_EMAIL_KEY) ?? ""

            // If no active session or user exists in Keychain, user is signed out
            if sessionId.isEmpty && userId.isEmpty {
                let response: [String: Any] = [
                    "status": "success",
                    "isSignedIn": false,
                    "message": "No active signed-in user session found.",
                    "platform": "ios"
                ]
                self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response), callbackId: command.callbackId)
                return
            }

            // We have an active session! Return signed-in user metadata
            var response: [String: Any] = [
                "status": "success",
                "isSignedIn": true,
                "userId": userId.isEmpty ? "user_shared_session" : userId,
                "firstName": firstName,
                "lastName": lastName,
                "email": email,
                "sessionId": sessionId,
                "platform": "ios"
            ]

            // Best-effort live refresh from Clerk /v1/client using Publishable Key
            let pk = self.inMemoryPublishableKey.isEmpty ? (self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_PUBLISHABLE_KEY) ?? "") : self.inMemoryPublishableKey
            if let host = self.getFrontendApiHost(publishableKey: pk), !host.isEmpty, var urlComponents = URLComponents(string: "https://\(host)/v1/client") {
                var queryItems = [URLQueryItem(name: "_clerk_js_version", value: "5.0.0")]
                if let dbJwt = self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_DEV_BROWSER_JWT_KEY), !dbJwt.isEmpty {
                    queryItems.append(URLQueryItem(name: "_clerk_db_jwt", value: dbJwt))
                }
                urlComponents.queryItems = queryItems

                if let url = urlComponents.url {
                    var request = URLRequest(url: url)
                    request.httpMethod = "GET"
                    request.setValue("Bearer \(pk)", forHTTPHeaderField: "Authorization")
                    if let dbJwt = self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_DEV_BROWSER_JWT_KEY), !dbJwt.isEmpty {
                        request.setValue(dbJwt, forHTTPHeaderField: "Clerk-Db-Jwt")
                    }

                    let semaphore = DispatchSemaphore(value: 0)
                    var responseJson: [String: Any]?
                    var statusCode: Int = 0

                    let task = URLSession.shared.dataTask(with: request) { data, resp, _ in
                        self.extractAndSaveDevBrowserJwt(response: resp)
                        if let httpResp = resp as? HTTPURLResponse {
                            statusCode = httpResp.statusCode
                        }
                        if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            responseJson = json
                        }
                        semaphore.signal()
                    }
                    task.resume()
                    _ = semaphore.wait(timeout: .now() + 3.0)

                    if (statusCode == 200 || statusCode == 304), let json = responseJson, let clientObj = json["client"] as? [String: Any],
                       let sessionsList = clientObj["sessions"] as? [[String: Any]], let activeSession = sessionsList.first(where: { ($0["id"] as? String) == sessionId }) ?? sessionsList.first,
                       let userObj = activeSession["user"] as? [String: Any] {

                        let freshUserId = userObj["id"] as? String ?? userId
                        let freshFirstName = userObj["first_name"] as? String ?? firstName
                        let freshLastName = userObj["last_name"] as? String ?? lastName

                        self.saveToKeychain(key: EchoPlugin.KEYCHAIN_USER_ID_KEY, value: freshUserId)
                        self.saveToKeychain(key: EchoPlugin.KEYCHAIN_FIRST_NAME_KEY, value: freshFirstName)
                        self.saveToKeychain(key: EchoPlugin.KEYCHAIN_LAST_NAME_KEY, value: freshLastName)

                        response["userId"] = freshUserId
                        response["firstName"] = freshFirstName
                        response["lastName"] = freshLastName
                    }
                }
            }

            self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response), callbackId: command.callbackId)
        })
    }

    @objc(signOut:)
    func signOut(command: CDVInvokedUrlCommand) {
        self.commandDelegate!.run(inBackground: {
            let sessionId = self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_SESSION_ID_KEY) ?? ""
            let pk = self.inMemoryPublishableKey.isEmpty ? (self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_PUBLISHABLE_KEY) ?? "") : self.inMemoryPublishableKey
            let sessionToken = self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_ACCOUNT_KEY) ?? ""

            // 1. Attempt server-side session revoke on Clerk
            if !sessionId.isEmpty, let host = self.getFrontendApiHost(publishableKey: pk), let url = URL(string: "https://\(host)/v1/client/sessions/\(sessionId)/remove") {
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                if !sessionToken.isEmpty {
                    req.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
                } else if !pk.isEmpty {
                    req.setValue("Bearer \(pk)", forHTTPHeaderField: "Authorization")
                }
                let sem = DispatchSemaphore(value: 0)
                URLSession.shared.dataTask(with: req) { _, _, _ in sem.signal() }.resume()
                _ = sem.wait(timeout: .now() + 3.0)
            }

            // 2. Delete all session & user keys from Keychain
            self.deleteFromKeychain(key: EchoPlugin.KEYCHAIN_ACCOUNT_KEY)
            self.deleteFromKeychain(key: EchoPlugin.KEYCHAIN_SESSION_ID_KEY)
            self.deleteFromKeychain(key: EchoPlugin.KEYCHAIN_USER_ID_KEY)
            self.deleteFromKeychain(key: EchoPlugin.KEYCHAIN_FIRST_NAME_KEY)
            self.deleteFromKeychain(key: EchoPlugin.KEYCHAIN_LAST_NAME_KEY)
            self.deleteFromKeychain(key: EchoPlugin.KEYCHAIN_EMAIL_KEY)

            // 3. Purge all Clerk cookies and dev tokens
            self.purgeAllClerkCookies()

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
                self.extractAndSaveDevBrowserJwt(response: response)
                if let httpResp = response as? HTTPURLResponse {
                    responseCode = httpResp.statusCode
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

    @objc(getKeychainAccessGroup:)
    func getKeychainAccessGroup(command: CDVInvokedUrlCommand) {
        self.commandDelegate!.run(inBackground: {
            let response: [String: Any] = [
                "status": "success",
                "accessGroup": "org.luvelo.dev.shared",
                "service": EchoPlugin.SHARED_KEYCHAIN_SERVICE,
                "platform": "ios"
            ]
            self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response), callbackId: command.callbackId)
        })
    }

    // MARK: - Hosted Authentication (ASWebAuthenticationSession)

    @objc(startHostedAuth:)
    func startHostedAuth(command: CDVInvokedUrlCommand) {
        self.commandDelegate!.run(inBackground: {
            let mode = command.argument(at: 0) as? String ?? "sign_in"
            let pk = self.inMemoryPublishableKey.isEmpty ? (self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_PUBLISHABLE_KEY) ?? "") : self.inMemoryPublishableKey
            guard let fapiHost = self.getFrontendApiHost(publishableKey: pk),
                  let portalHost = self.getAccountPortalHost(publishableKey: pk), !portalHost.isEmpty else {
                let response: [String: Any] = [
                    "status": "error",
                    "message": "Clerk publishable key is missing or invalid. Please call initializeClerk(publishableKey) first.",
                    "errorCode": "clerk_not_initialized",
                    "platform": "ios"
                ]
                self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: response), callbackId: command.callbackId)
                return
            }

            let path = (mode.lowercased() == "sign_up") ? "/sign-up" : "/sign-in"
            guard var urlComponents = URLComponents(string: "https://\(portalHost)\(path)") else {
                let response: [String: Any] = [
                    "status": "error",
                    "message": "Invalid Account Portal URL for host: \(portalHost)",
                    "errorCode": "invalid_url",
                    "platform": "ios"
                ]
                self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: response), callbackId: command.callbackId)
                return
            }

            let bundleId = Bundle.main.bundleIdentifier ?? "org.luvelo.dev.ClerkApp2"
            let callbackScheme = bundleId
            let redirectUrl = "\(bundleId)://callback"

            var queryItems = [
                URLQueryItem(name: "redirect_url", value: redirectUrl),
                URLQueryItem(name: "after_sign_in_url", value: redirectUrl),
                URLQueryItem(name: "after_sign_up_url", value: redirectUrl),
                URLQueryItem(name: "fallback_redirect_url", value: redirectUrl),
                URLQueryItem(name: "sign_in_force_redirect_url", value: redirectUrl),
                URLQueryItem(name: "sign_up_force_redirect_url", value: redirectUrl),
                URLQueryItem(name: "_clerk_js_version", value: "5.0.0")
            ]
            if let dbJwt = self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_DEV_BROWSER_JWT_KEY), !dbJwt.isEmpty {
                queryItems.append(URLQueryItem(name: "_clerk_db_jwt", value: dbJwt))
            }
            urlComponents.queryItems = queryItems

            guard let authURL = urlComponents.url else {
                let response: [String: Any] = [
                    "status": "error",
                    "message": "Failed to generate authentication URL",
                    "errorCode": "url_generation_failed",
                    "platform": "ios"
                ]
                self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: response), callbackId: command.callbackId)
                return
            }

            DispatchQueue.main.async {
                self.authSession = ASWebAuthenticationSession(url: authURL, callbackURLScheme: callbackScheme) { callbackURL, error in
                    self.authSession = nil
                    if let error = error {
                        let nsError = error as NSError
                        if nsError.domain == ASWebAuthenticationSessionErrorDomain && nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                            let response: [String: Any] = [
                                "status": "cancelled",
                                "message": "User cancelled authentication",
                                "platform": "ios"
                            ]
                            self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: response), callbackId: command.callbackId)
                        } else {
                            let response: [String: Any] = [
                                "status": "error",
                                "message": error.localizedDescription,
                                "errorCode": "hosted_auth_failed",
                                "platform": "ios"
                            ]
                            self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: response), callbackId: command.callbackId)
                        }
                        return
                    }

                    guard let callbackURL = callbackURL else {
                        let response: [String: Any] = [
                            "status": "error",
                            "message": "Authentication completed without callback URL",
                            "errorCode": "no_callback_url",
                            "platform": "ios"
                        ]
                        self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: response), callbackId: command.callbackId)
                        return
                    }

                    self.handleHostedAuthCallback(callbackURL: callbackURL, host: fapiHost, pk: pk, command: command)
                }

                if #available(iOS 13.0, *) {
                    self.authSession?.presentationContextProvider = self
                    self.authSession?.prefersEphemeralWebBrowserSession = false
                }

                self.authSession?.start()
            }
        })
    }

    private func handleHostedAuthCallback(callbackURL: URL, host: String, pk: String, command: CDVInvokedUrlCommand) {
        self.commandDelegate!.run(inBackground: {
            var createdSessionId = ""

            if let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) {
                if let queryItems = components.queryItems {
                    for item in queryItems {
                        if item.name == "__clerk_created_session" || item.name == "created_session_id" || item.name == "session_id" {
                            createdSessionId = item.value ?? ""
                        }
                        if (item.name == "__clerk_db_jwt" || item.name == "_clerk_db_jwt"), let dbJwt = item.value, !dbJwt.isEmpty {
                            self.saveToKeychain(key: EchoPlugin.KEYCHAIN_DEV_BROWSER_JWT_KEY, value: dbJwt)
                        }
                    }
                }
            }

            if !createdSessionId.isEmpty {
                self.saveToKeychain(key: EchoPlugin.KEYCHAIN_SESSION_ID_KEY, value: createdSessionId)
            }

            // Live fetch user session from /v1/client
            guard var urlComponents = URLComponents(string: "https://\(host)/v1/client") else {
                let response: [String: Any] = [
                    "status": "success",
                    "message": "Hosted authentication successful",
                    "sessionId": createdSessionId,
                    "platform": "ios"
                ]
                self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response), callbackId: command.callbackId)
                return
            }

            var queryItems = [URLQueryItem(name: "_clerk_js_version", value: "5.0.0")]
            if let dbJwt = self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_DEV_BROWSER_JWT_KEY), !dbJwt.isEmpty {
                queryItems.append(URLQueryItem(name: "_clerk_db_jwt", value: dbJwt))
            }
            urlComponents.queryItems = queryItems

            guard let url = urlComponents.url else {
                let response: [String: Any] = [
                    "status": "success",
                    "message": "Hosted authentication successful",
                    "sessionId": createdSessionId,
                    "platform": "ios"
                ]
                self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response), callbackId: command.callbackId)
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            if !pk.isEmpty {
                request.setValue("Bearer \(pk)", forHTTPHeaderField: "Authorization")
            }
            if let dbJwt = self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_DEV_BROWSER_JWT_KEY), !dbJwt.isEmpty {
                request.setValue(dbJwt, forHTTPHeaderField: "Clerk-Db-Jwt")
            }

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                self.extractAndSaveDevBrowserJwt(response: response)

                var userId = ""
                var firstName = ""
                var lastName = ""
                var email = ""
                var jwtToken = ""

                if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let clientObj = json["client"] as? [String: Any] {

                    if createdSessionId.isEmpty, let activeSessId = clientObj["active_session_id"] as? String {
                        createdSessionId = activeSessId
                    }

                    if let sessionsList = clientObj["sessions"] as? [[String: Any]] {
                        let activeSess = sessionsList.first(where: { ($0["id"] as? String) == createdSessionId }) ?? sessionsList.first
                        if let sess = activeSess {
                            if createdSessionId.isEmpty, let sId = sess["id"] as? String {
                                createdSessionId = sId
                            }
                            if let lastActiveToken = sess["last_active_token"] as? [String: Any], let jwt = lastActiveToken["jwt"] as? String {
                                jwtToken = jwt
                            }
                            if let userObj = sess["user"] as? [String: Any] {
                                userId = userObj["id"] as? String ?? ""
                                firstName = userObj["first_name"] as? String ?? ""
                                lastName = userObj["last_name"] as? String ?? ""
                                if let emailList = userObj["email_addresses"] as? [[String: Any]], let firstEmail = emailList.first {
                                    email = firstEmail["email_address"] as? String ?? ""
                                }
                            }
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
                if !userId.isEmpty {
                    self.saveToKeychain(key: EchoPlugin.KEYCHAIN_USER_ID_KEY, value: userId)
                }
                if !firstName.isEmpty {
                    self.saveToKeychain(key: EchoPlugin.KEYCHAIN_FIRST_NAME_KEY, value: firstName)
                }
                if !lastName.isEmpty {
                    self.saveToKeychain(key: EchoPlugin.KEYCHAIN_LAST_NAME_KEY, value: lastName)
                }
                if !email.isEmpty {
                    self.saveToKeychain(key: EchoPlugin.KEYCHAIN_EMAIL_KEY, value: email)
                }

                let resultResponse: [String: Any] = [
                    "status": "success",
                    "message": "Hosted authentication successful",
                    "sessionId": createdSessionId,
                    "userId": userId,
                    "firstName": firstName,
                    "lastName": lastName,
                    "email": email,
                    "platform": "ios"
                ]
                self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_OK, messageAs: resultResponse), callbackId: command.callbackId)
            }
            task.resume()
        })
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension EchoPlugin: ASWebAuthenticationPresentationContextProviding {
    @available(iOS 12.0, *)
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let window = self.viewController?.view?.window {
            return window
        }
        if #available(iOS 13.0, *) {
            if let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow }) {
                return window
            }
        }
        return ASPresentationAnchor()
    }
}

