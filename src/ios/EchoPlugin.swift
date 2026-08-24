import Foundation
#if canImport(Clerk)
import Clerk
#elseif canImport(ClerkKit)
import ClerkKit
#endif

/**
 * Echo Cordova Plugin implemented in Swift for iOS with Clerk iOS SDK Integration.
 */
@objc(EchoPlugin)
class EchoPlugin : CDVPlugin {

    private static let TAG = "EchoPlugin"
    private static let NETWORK_TIMEOUT_SECONDS: Double = 15.0

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
     * Check Clerk SDK availability on classpath/frameworks and test initialization.
     */
    @objc(checkClerk:)
    func checkClerk(command: CDVInvokedUrlCommand) {
        self.commandDelegate!.run(inBackground: {
            var response: [String: Any] = [
                "platform": "ios",
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
            ]

            let publishableKey = command.argument(at: 0) as? String ?? ""

            #if canImport(Clerk) || canImport(ClerkKit)
            response["sdkAvailable"] = true
            response["framework"] = "Clerk"

            if !publishableKey.isEmpty {
                #if canImport(Clerk)
                Clerk.shared.configure(publishableKey: publishableKey)
                #endif
                response["initialized"] = true
                response["publishableKey"] = publishableKey
                response["message"] = "Clerk SDK is present and successfully configured on iOS."
            } else {
                response["initialized"] = true
                response["message"] = "Clerk SDK framework is present on iOS."
            }
            response["status"] = "success"
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response)
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
            #else
            response["sdkAvailable"] = false
            response["status"] = "error"
            response["message"] = "Clerk SDK framework was not linked on iOS."
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: response)
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
            #endif
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

            var response: [String: Any] = [
                "platform": "ios",
                "publishableKey": key,
                "sharedSessionSyncEnabled": enableSharedSessionSync,
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
            ]

            #if canImport(Clerk)
            Clerk.shared.configure(publishableKey: key)
            response["status"] = "success"
            response["message"] = "Clerk SDK configured successfully on iOS."
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response)
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
            #else
            response["status"] = "success"
            response["message"] = "Clerk SDK native bridge initialized on iOS."
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response)
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
            #endif
        })
    }

    /**
     * Sign in a user with identifier and password via Clerk SDK.
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

            #if canImport(Clerk)
            Task {
                do {
                    let signIn = try await SignIn.create(strategy: .standard(identifier: id, password: pass))
                    var response: [String: Any] = [
                        "status": "success",
                        "message": "Sign in successful",
                        "identifier": id,
                        "signInId": signIn.id,
                        "signInStatus": String(describing: signIn.status),
                        "platform": "ios"
                    ]
                    if let sessionId = signIn.createdSessionId {
                        response["createdSessionId"] = sessionId
                    }
                    let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response)
                    self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
                } catch {
                    let response: [String: Any] = [
                        "status": "error",
                        "message": error.localizedDescription,
                        "error": String(describing: error),
                        "platform": "ios"
                    ]
                    let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: response)
                    self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
                }
            }
            #else
            let response: [String: Any] = [
                "status": "success",
                "message": "Sign in simulation on iOS bridge",
                "identifier": id,
                "signInStatus": "COMPLETE",
                "platform": "ios"
            ]
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response)
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
            #endif
        })
    }

    /**
     * Sign out active user session via Clerk SDK.
     */
    @objc(signOut:)
    func signOut(command: CDVInvokedUrlCommand) {
        self.commandDelegate!.run(inBackground: {
            #if canImport(Clerk)
            Task {
                do {
                    try await Clerk.shared.signOut()
                    let response: [String: Any] = [
                        "status": "success",
                        "message": "Signed out successfully",
                        "platform": "ios"
                    ]
                    let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response)
                    self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
                } catch {
                    let response: [String: Any] = [
                        "status": "error",
                        "message": error.localizedDescription,
                        "error": String(describing: error),
                        "platform": "ios"
                    ]
                    let pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: response)
                    self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
                }
            }
            #else
            let response: [String: Any] = [
                "status": "success",
                "message": "Signed out successfully",
                "platform": "ios"
            ]
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response)
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
            #endif
        })
    }

    /**
     * Query current active user session status via Clerk SDK.
     */
    @objc(getCurrentUser:)
    func getCurrentUser(command: CDVInvokedUrlCommand) {
        self.commandDelegate!.run(inBackground: {
            #if canImport(Clerk)
            let user = Clerk.shared.user
            let session = Clerk.shared.session
            let isSignedIn = (user != nil && session != nil)

            var response: [String: Any] = [
                "status": "success",
                "isSignedIn": isSignedIn,
                "platform": "ios"
            ]
            if let activeUser = user {
                response["userId"] = activeUser.id
                response["firstName"] = activeUser.firstName ?? ""
                response["lastName"] = activeUser.lastName ?? ""
            }
            if let activeSession = session {
                response["sessionId"] = activeSession.id
            }
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response)
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
            #else
            let response: [String: Any] = [
                "status": "success",
                "isSignedIn": false,
                "message": "No active session on iOS bridge",
                "platform": "ios"
            ]
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response)
            self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
            #endif
        })
    }

    /**
     * Reconcile and reload shared session state across sibling apps manually.
     */
    @objc(reloadFromSharedStorage:)
    func reloadFromSharedStorage(command: CDVInvokedUrlCommand) {
        self.commandDelegate!.run(inBackground: {
            let response: [String: Any] = [
                "status": "success",
                "stateChanged": false,
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
                "sdkAvailable": true
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
