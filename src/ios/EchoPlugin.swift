import Foundation
import Cordova

/**
 * Echo Cordova Plugin implemented in Swift for iOS.
 */
@objc(EchoPlugin)
class EchoPlugin : CDVPlugin {

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
     * Placeholder method for Clerk SDK status check prior to Clerk SDK integration
     */
    @objc(checkClerk:)
    func checkClerk(command: CDVInvokedUrlCommand) {
        let response: [String: Any] = [
            "status": "warning",
            "message": "Clerk SDK for iOS is not yet integrated. Native Swift bridge is active.",
            "platform": "ios"
        ]
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: response)
        self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
    }
}
