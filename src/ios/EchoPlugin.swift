import Foundation
import Security
import WebKit
import AuthenticationServices
import CommonCrypto

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
    private var cachedClientToken: String = ""
    private var authSession: ASWebAuthenticationSession?
    private var activeHostedAuthState: String?
    private var activeHostedAuthVerifier: String?

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
        request.httpShouldHandleCookies = false
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

            if userId.isEmpty && !jwtToken.isEmpty {
                if let sub = self.extractUserIdFromJwt(token: jwtToken) {
                    userId = sub
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
            var userId = self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_USER_ID_KEY) ?? ""
            var firstName = self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_FIRST_NAME_KEY) ?? ""
            var lastName = self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_LAST_NAME_KEY) ?? ""
            var email = self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_EMAIL_KEY) ?? ""
            let sessionToken = self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_ACCOUNT_KEY) ?? ""

            // Instant recovery: If userId is missing, extract sub claim from sessionToken JWT
            if (userId.isEmpty || userId == "user_shared_session") && !sessionToken.isEmpty {
                if let sub = self.extractUserIdFromJwt(token: sessionToken) {
                    userId = sub
                    self.saveToKeychain(key: EchoPlugin.KEYCHAIN_USER_ID_KEY, value: sub)
                }
            }

            // If no active session or token exists in Keychain, user is signed out
            if sessionId.isEmpty && userId.isEmpty && sessionToken.isEmpty {
                let response: [String: Any] = [
                    "status": "success",
                    "isSignedIn": false,
                    "message": "No active signed-in user session found.",
                    "platform": "ios"
                ]
                self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response), callbackId: command.callbackId)
                return
            }

            // Best-effort live refresh from Clerk using Session Touch or Client endpoint
            let pk = self.inMemoryPublishableKey.isEmpty ? (self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_PUBLISHABLE_KEY) ?? "") : self.inMemoryPublishableKey
            if let host = self.getFrontendApiHost(publishableKey: pk), !host.isEmpty {
                let authHeaderToUse = !sessionToken.isEmpty ? (!sessionToken.starts(with: "Bearer ") ? "Bearer \(sessionToken)" : sessionToken) : (!self.cachedClientToken.isEmpty ? self.cachedClientToken : "Bearer \(pk)")

                // 1. If sessionId is known, touch the session to get full session + user metadata
                if !sessionId.isEmpty, let touchUrl = URL(string: "https://\(host)/v1/client/sessions/\(sessionId)/touch") {
                    var touchReq = URLRequest(url: touchUrl)
                    touchReq.httpMethod = "POST"
                    touchReq.httpShouldHandleCookies = false
                    touchReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                    touchReq.setValue(authHeaderToUse, forHTTPHeaderField: "Authorization")
                    touchReq.httpBody = "active_organization_id=&intent=select_org".data(using: .utf8)

                    let sem = DispatchSemaphore(value: 0)
                    URLSession.shared.dataTask(with: touchReq) { data, _, _ in
                        if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            let sessObj = json["response"] as? [String: Any] ?? json["session"] as? [String: Any]
                            if let sess = sessObj {
                                if let userObj = sess["user"] as? [String: Any] {
                                    if let uId = userObj["id"] as? String, !uId.isEmpty { userId = uId }
                                    if let fName = userObj["first_name"] as? String { firstName = fName }
                                    if let lName = userObj["last_name"] as? String { lastName = lName }
                                    if let emailList = userObj["email_addresses"] as? [[String: Any]], let firstEmail = emailList.first, let eAddr = firstEmail["email_address"] as? String {
                                        email = eAddr
                                    }
                                } else if let pubData = sess["public_user_data"] as? [String: Any] {
                                    if let uId = pubData["user_id"] as? String, !uId.isEmpty { userId = uId }
                                    if let fName = pubData["first_name"] as? String { firstName = fName }
                                    if let lName = pubData["last_name"] as? String { lastName = lName }
                                    if let idf = pubData["identifier"] as? String { email = idf }
                                }
                                if let lastTok = sess["last_active_token"] as? [String: Any], let jwt = lastTok["jwt"] as? String, !jwt.isEmpty {
                                    self.saveToKeychain(key: EchoPlugin.KEYCHAIN_ACCOUNT_KEY, value: jwt)
                                    if userId.isEmpty || userId == "user_shared_session" {
                                        if let sub = self.extractUserIdFromJwt(token: jwt) { userId = sub }
                                    }
                                }
                            }
                        }
                        sem.signal()
                    }.resume()
                    _ = sem.wait(timeout: .now() + 3.0)
                }

                // 2. Persist any refreshed metadata to Keychain
                if !userId.isEmpty && userId != "user_shared_session" {
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
            }

            let effectiveUserId = (!userId.isEmpty && userId != "user_shared_session") ? userId : (!sessionId.isEmpty ? sessionId : "user_shared_session")

            let response: [String: Any] = [
                "status": "success",
                "isSignedIn": true,
                "userId": effectiveUserId,
                "firstName": firstName,
                "lastName": lastName,
                "email": email,
                "sessionId": sessionId,
                "platform": "ios"
            ]
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

    // MARK: - PKCE & Cryptography Helpers

    private func generateRandomBytes(count: Int) -> Data? {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else { return nil }
        return Data(bytes)
    }

    private func sha256(data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            if let addr = buffer.baseAddress {
                _ = CC_SHA256(addr, CC_LONG(data.count), &hash)
            }
        }
        return Data(hash)
    }

    private func base64UrlEncode(data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func urlEncode(_ string: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "!*'();:@&=+$,/?%#[]")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }

    private func extractUserIdFromJwt(token: String) -> String? {
        let cleanToken = token.replacingOccurrences(of: "Bearer ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = cleanToken.components(separatedBy: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = json["sub"] as? String, !sub.isEmpty else {
            return nil
        }
        return sub
    }

    // MARK: - Client Token Resolver

    private func fetchClientToken(host: String, publishableKey: String, completion: @escaping (_ token: String?, _ error: String?) -> Void) {
        if !self.cachedClientToken.isEmpty {
            completion(self.cachedClientToken, nil)
            return
        }

        guard let url = URL(string: "https://\(host)/v1/client") else {
            completion(nil, "Invalid Clerk Frontend API URL")
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpShouldHandleCookies = false
        req.setValue("Bearer \(publishableKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data()

        let task = URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error {
                completion(nil, "Network error fetching client token: \(error.localizedDescription)")
                return
            }

            guard let httpResp = response as? HTTPURLResponse else {
                completion(nil, "No HTTP response received from Clerk client endpoint")
                return
            }

            self.extractAndSaveDevBrowserJwt(response: response)

            var authHeader: String? = nil
            if #available(iOS 13.0, *) {
                authHeader = httpResp.value(forHTTPHeaderField: "Authorization")
            }
            if authHeader == nil || authHeader?.isEmpty == true {
                for (k, v) in httpResp.allHeaderFields {
                    if "\(k)".lowercased() == "authorization" {
                        authHeader = v as? String
                        break
                    }
                }
            }

            if let auth = authHeader, !auth.isEmpty {
                self.cachedClientToken = auth
                completion(auth, nil)
                return
            }

            var errMsg = "HTTP \(httpResp.statusCode): Failed to obtain client token"
            if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errors = json["errors"] as? [[String: Any]], let firstErr = errors.first {
                errMsg = firstErr["long_message"] as? String ?? firstErr["message"] as? String ?? errMsg
            }
            completion(nil, errMsg)
        }
        task.resume()
    }

    // MARK: - Hosted Authentication Initiation (POST /v1/client/hosted_auth)

    private func requestHostedAuthUrl(host: String, clientToken: String, redirectUrl: String, codeChallenge: String, state: String, mode: String, completion: @escaping (_ authUrl: String?, _ errorMessage: String?) -> Void) {
        guard let url = URL(string: "https://\(host)/v1/client/hosted_auth") else {
            completion(nil, "Invalid hosted auth URL")
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpShouldHandleCookies = false
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(clientToken, forHTTPHeaderField: "Authorization")
        if let dbJwt = self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_DEV_BROWSER_JWT_KEY), !dbJwt.isEmpty {
            req.setValue(dbJwt, forHTTPHeaderField: "Clerk-Db-Jwt")
        }

        let modeParam = (mode.lowercased() == "sign_up") ? "sign-up" : "sign-in"
        let postParams: [String: String] = [
            "redirect_url": redirectUrl,
            "code_challenge": codeChallenge,
            "state": state,
            "mode": modeParam
        ]

        let bodyString = postParams.map { "\(self.urlEncode($0.key))=\(self.urlEncode($0.value))" }.joined(separator: "&")
        req.httpBody = bodyString.data(using: .utf8)

        let task = URLSession.shared.dataTask(with: req) { data, response, error in
            self.extractAndSaveDevBrowserJwt(response: response)
            if let error = error {
                completion(nil, "Network error: \(error.localizedDescription)")
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(nil, "Invalid response from Clerk hosted auth endpoint")
                return
            }

            if let respObj = json["response"] as? [String: Any],
               let authUrl = respObj["url"] as? String, !authUrl.isEmpty {
                completion(authUrl, nil)
                return
            }

            if let errors = json["errors"] as? [[String: Any]], let firstErr = errors.first {
                let msg = firstErr["long_message"] as? String ?? firstErr["message"] as? String ?? "Unknown Clerk error"
                completion(nil, msg)
                return
            }

            completion(nil, "Hosted auth response did not contain a valid URL")
        }
        task.resume()
    }

    // MARK: - Hosted Authentication (ASWebAuthenticationSession)

    @objc(startHostedAuth:)
    func startHostedAuth(command: CDVInvokedUrlCommand) {
        self.commandDelegate!.run(inBackground: {
            let mode = command.argument(at: 0) as? String ?? "sign_in"
            let pk = self.inMemoryPublishableKey.isEmpty ? (self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_PUBLISHABLE_KEY) ?? "") : self.inMemoryPublishableKey
            guard let fapiHost = self.getFrontendApiHost(publishableKey: pk), !fapiHost.isEmpty else {
                let response: [String: Any] = [
                    "status": "error",
                    "message": "Clerk publishable key is missing or invalid. Please call initializeClerk(publishableKey) first.",
                    "errorCode": "clerk_not_initialized",
                    "platform": "ios"
                ]
                self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: response), callbackId: command.callbackId)
                return
            }

            // 1. Generate cryptographic PKCE & state parameters
            guard let randomBytes = self.generateRandomBytes(count: 32) else {
                let response: [String: Any] = [
                    "status": "error",
                    "message": "Failed to generate cryptographic random bytes for PKCE.",
                    "errorCode": "crypto_error",
                    "platform": "ios"
                ]
                self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: response), callbackId: command.callbackId)
                return
            }

            let codeVerifier = randomBytes.map { String(format: "%02x", $0) }.joined()
            guard let verifierData = codeVerifier.data(using: .utf8) else {
                let response: [String: Any] = [
                    "status": "error",
                    "message": "Failed to encode PKCE code verifier.",
                    "errorCode": "crypto_error",
                    "platform": "ios"
                ]
                self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: response), callbackId: command.callbackId)
                return
            }
            let codeChallenge = self.base64UrlEncode(data: self.sha256(data: verifierData))
            let state = UUID().uuidString

            self.activeHostedAuthState = state
            self.activeHostedAuthVerifier = codeVerifier

            let bundleId = Bundle.main.bundleIdentifier ?? "org.luvelo.dev.ClerkApp2"
            let callbackScheme = bundleId
            let redirectUrl = "\(bundleId)://callback"

            // Ensure clean state before requesting client token
            self.purgeAllClerkCookies()

            // 2. Obtain Client JWT from Clerk FAPI
            self.fetchClientToken(host: fapiHost, publishableKey: pk) { clientToken, clientErr in
                guard let tokenToUse = clientToken, !tokenToUse.isEmpty else {
                    let response: [String: Any] = [
                        "status": "error",
                        "message": "Failed to initiate hosted auth: \(clientErr ?? "Unable to obtain Clerk client token")",
                        "errorCode": "hosted_auth_init_failed",
                        "platform": "ios"
                    ]
                    self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: response), callbackId: command.callbackId)
                    return
                }

                // 3. Initiate Hosted Auth with Clerk FAPI to obtain signed Account Portal URL
                self.requestHostedAuthUrl(host: fapiHost, clientToken: tokenToUse, redirectUrl: redirectUrl, codeChallenge: codeChallenge, state: state, mode: mode) { authUrlStr, errorMsg in
                    if let authUrlStr = authUrlStr {
                        self.launchWebAuthSession(urlStr: authUrlStr, callbackScheme: callbackScheme, fapiHost: fapiHost, pk: pk, command: command)
                    } else {
                        // If token expired/signed_out or dev_browser_unauthenticated, purge and retry once with fresh client token
                        let firstError = errorMsg ?? "Unknown error"
                        self.cachedClientToken = ""
                        self.purgeAllClerkCookies()
                        self.fetchClientToken(host: fapiHost, publishableKey: pk) { freshToken, freshErr in
                            guard let fresh = freshToken, !fresh.isEmpty else {
                                let response: [String: Any] = [
                                    "status": "error",
                                    "message": "Failed to initiate hosted auth: \(freshErr ?? firstError)",
                                    "errorCode": "hosted_auth_init_failed",
                                    "platform": "ios"
                                ]
                                self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: response), callbackId: command.callbackId)
                                return
                            }

                            self.requestHostedAuthUrl(host: fapiHost, clientToken: fresh, redirectUrl: redirectUrl, codeChallenge: codeChallenge, state: state, mode: mode) { retryAuthUrl, retryError in
                                if let retryAuthUrl = retryAuthUrl {
                                    self.launchWebAuthSession(urlStr: retryAuthUrl, callbackScheme: callbackScheme, fapiHost: fapiHost, pk: pk, command: command)
                                } else {
                                    let response: [String: Any] = [
                                        "status": "error",
                                        "message": "Failed to initiate hosted auth: \(retryError ?? firstError)",
                                        "errorCode": "hosted_auth_init_failed",
                                        "platform": "ios"
                                    ]
                                    self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: response), callbackId: command.callbackId)
                                }
                            }
                        }
                    }
                }
            }
        })
    }

    private func launchWebAuthSession(urlStr: String, callbackScheme: String, fapiHost: String, pk: String, command: CDVInvokedUrlCommand) {
        guard let authURL = URL(string: urlStr) else {
            let response: [String: Any] = [
                "status": "error",
                "message": "Failed to parse hosted auth URL: \(urlStr)",
                "errorCode": "invalid_url",
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
    }

    private func handleHostedAuthCallback(callbackURL: URL, host: String, pk: String, command: CDVInvokedUrlCommand) {
        self.commandDelegate!.run(inBackground: {
            var callbackState = ""
            var rotatingTokenNonce = ""
            var createdSessionId = ""

            if let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
               let queryItems = components.queryItems {
                for item in queryItems {
                    if item.name == "state" {
                        callbackState = item.value ?? ""
                    } else if item.name == "rotating_token_nonce" || item.name == "rotatingTokenNonce" {
                        rotatingTokenNonce = item.value ?? ""
                    } else if item.name == "created_session_id" || item.name == "createdSessionId" || item.name == "__clerk_created_session" || item.name == "session_id" {
                        createdSessionId = item.value ?? ""
                    } else if item.name == "__clerk_db_jwt" || item.name == "_clerk_db_jwt" {
                        if let dbJwt = item.value, !dbJwt.isEmpty {
                            self.saveToKeychain(key: EchoPlugin.KEYCHAIN_DEV_BROWSER_JWT_KEY, value: dbJwt)
                        }
                    }
                }
            }

            // Verify state parameter to prevent CSRF attacks
            if let expectedState = self.activeHostedAuthState, !expectedState.isEmpty, !callbackState.isEmpty {
                guard callbackState == expectedState else {
                    let response: [String: Any] = [
                        "status": "error",
                        "message": "Hosted auth callback state mismatch. Possible CSRF attack detected.",
                        "errorCode": "state_mismatch",
                        "platform": "ios"
                    ]
                    self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: response), callbackId: command.callbackId)
                    return
                }
            }

            let codeVerifier = self.activeHostedAuthVerifier ?? ""
            self.activeHostedAuthState = nil
            self.activeHostedAuthVerifier = nil

            // 4. Redeem session via POST /v1/client (_method=GET)
            guard let redeemUrl = URL(string: "https://\(host)/v1/client") else {
                let response: [String: Any] = [
                    "status": "error",
                    "message": "Invalid client endpoint URL",
                    "errorCode": "invalid_url",
                    "platform": "ios"
                ]
                self.commandDelegate!.send(CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: response), callbackId: command.callbackId)
                return
            }

            var redeemReq = URLRequest(url: redeemUrl)
            redeemReq.httpMethod = "POST"
            redeemReq.httpShouldHandleCookies = false
            redeemReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let authHeaderToUse = !self.cachedClientToken.isEmpty ? self.cachedClientToken : "Bearer \(pk)"
            redeemReq.setValue(authHeaderToUse, forHTTPHeaderField: "Authorization")
            if let dbJwt = self.loadFromKeychain(key: EchoPlugin.KEYCHAIN_DEV_BROWSER_JWT_KEY), !dbJwt.isEmpty {
                redeemReq.setValue(dbJwt, forHTTPHeaderField: "Clerk-Db-Jwt")
            }

            let redeemParams: [String: String] = [
                "_method": "GET",
                "rotating_token_nonce": rotatingTokenNonce,
                "rotatingTokenNonce": rotatingTokenNonce,
                "code_verifier": codeVerifier,
                "codeVerifier": codeVerifier
            ]

            let redeemBody = redeemParams.map { "\(self.urlEncode($0.key))=\(self.urlEncode($0.value))" }.joined(separator: "&")
            redeemReq.httpBody = redeemBody.data(using: .utf8)

            let task = URLSession.shared.dataTask(with: redeemReq) { data, response, error in
                self.extractAndSaveDevBrowserJwt(response: response)

                var jwtToken = ""
                if let httpResp = response as? HTTPURLResponse {
                    var authHeader: String? = nil
                    if #available(iOS 13.0, *) {
                        authHeader = httpResp.value(forHTTPHeaderField: "Authorization")
                    }
                    if authHeader == nil || authHeader?.isEmpty == true {
                        for (k, v) in httpResp.allHeaderFields {
                            if "\(k)".lowercased() == "authorization" {
                                authHeader = v as? String
                                break
                            }
                        }
                    }
                    if let auth = authHeader, !auth.isEmpty {
                        jwtToken = auth
                        self.cachedClientToken = auth
                    }
                }

                var userId = ""
                var firstName = ""
                var lastName = ""
                var email = ""

                if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let clientObj = json["client"] as? [String: Any] ?? json["response"] as? [String: Any]

                    if let client = clientObj {
                        if createdSessionId.isEmpty, let activeSessId = client["active_session_id"] as? String {
                            createdSessionId = activeSessId
                        }
                        if let sessionsList = client["sessions"] as? [[String: Any]] {
                            let activeSess = sessionsList.first(where: { ($0["id"] as? String) == createdSessionId }) ?? sessionsList.first
                            if let sess = activeSess {
                                if createdSessionId.isEmpty, let sId = sess["id"] as? String {
                                    createdSessionId = sId
                                }
                                if let lastActiveToken = sess["last_active_token"] as? [String: Any], let jwt = lastActiveToken["jwt"] as? String, !jwt.isEmpty {
                                    jwtToken = jwt
                                    self.cachedClientToken = jwt
                                }
                                if let userObj = sess["user"] as? [String: Any] {
                                    userId = userObj["id"] as? String ?? ""
                                    firstName = userObj["first_name"] as? String ?? ""
                                    lastName = userObj["last_name"] as? String ?? ""
                                    if let emailList = userObj["email_addresses"] as? [[String: Any]], let firstEmail = emailList.first {
                                        email = firstEmail["email_address"] as? String ?? ""
                                    }
                                }
                                if userId.isEmpty, let pubData = sess["public_user_data"] as? [String: Any] {
                                    userId = pubData["user_id"] as? String ?? ""
                                    if firstName.isEmpty { firstName = pubData["first_name"] as? String ?? "" }
                                    if lastName.isEmpty { lastName = pubData["last_name"] as? String ?? "" }
                                    if email.isEmpty { email = pubData["identifier"] as? String ?? "" }
                                }
                            }
                        }
                    }
                }

                // Fallback 1: Extract userId directly from session JWT sub claim
                if userId.isEmpty && !jwtToken.isEmpty {
                    if let sub = self.extractUserIdFromJwt(token: jwtToken) {
                        userId = sub
                    }
                }

                // Fallback 2: Query Clerk's session touch endpoint using createdSessionId
                if userId.isEmpty && !createdSessionId.isEmpty {
                    if let touchUrl = URL(string: "https://\(host)/v1/client/sessions/\(createdSessionId)/touch") {
                        var touchReq = URLRequest(url: touchUrl)
                        touchReq.httpMethod = "POST"
                        touchReq.httpShouldHandleCookies = false
                        touchReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                        let touchAuth = !jwtToken.isEmpty ? (!jwtToken.starts(with: "Bearer ") ? "Bearer \(jwtToken)" : jwtToken) : authHeaderToUse
                        touchReq.setValue(touchAuth, forHTTPHeaderField: "Authorization")
                        touchReq.httpBody = "active_organization_id=&intent=select_org".data(using: .utf8)
                        let sem = DispatchSemaphore(value: 0)
                        URLSession.shared.dataTask(with: touchReq) { tData, _, _ in
                            if let tData = tData, let tJson = try? JSONSerialization.jsonObject(with: tData) as? [String: Any] {
                                let sessObj = tJson["response"] as? [String: Any] ?? tJson["session"] as? [String: Any]
                                if let sess = sessObj {
                                    if let uObj = sess["user"] as? [String: Any] {
                                        userId = uObj["id"] as? String ?? userId
                                        if firstName.isEmpty { firstName = uObj["first_name"] as? String ?? "" }
                                        if lastName.isEmpty { lastName = uObj["last_name"] as? String ?? "" }
                                        if email.isEmpty, let emailList = uObj["email_addresses"] as? [[String: Any]], let firstEmail = emailList.first {
                                            email = firstEmail["email_address"] as? String ?? ""
                                        }
                                    } else if let pubData = sess["public_user_data"] as? [String: Any] {
                                        userId = pubData["user_id"] as? String ?? userId
                                        if firstName.isEmpty { firstName = pubData["first_name"] as? String ?? "" }
                                        if lastName.isEmpty { lastName = pubData["last_name"] as? String ?? "" }
                                        if email.isEmpty { email = pubData["identifier"] as? String ?? "" }
                                    }
                                    if let lastTok = sess["last_active_token"] as? [String: Any], let tok = lastTok["jwt"] as? String, !tok.isEmpty {
                                        jwtToken = tok
                                        if userId.isEmpty, let sub = self.extractUserIdFromJwt(token: tok) {
                                            userId = sub
                                        }
                                    }
                                }
                            }
                            sem.signal()
                        }.resume()
                        _ = sem.wait(timeout: .now() + 3.0)
                    }
                }

                // Persist session to Shared Keychain
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

                let effectiveUserId = !userId.isEmpty ? userId : (!createdSessionId.isEmpty ? createdSessionId : "user_shared_session")

                let resultResponse: [String: Any] = [
                    "status": "success",
                    "message": "Hosted authentication successful",
                    "sessionId": createdSessionId,
                    "userId": effectiveUserId,
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

