package org.apache.cordova.plugin.echo

import org.apache.cordova.CordovaPlugin
import org.apache.cordova.CallbackContext
import org.apache.cordova.PluginResult
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import android.util.Log
import com.clerk.api.Clerk

/**
 * Echo Cordova Plugin implemented in Kotlin with Clerk Android SDK Integration.
 */
class Echo : CordovaPlugin() {

    companion object {
        private const val TAG = "EchoPlugin"
    }

    override fun execute(
        action: String,
        args: JSONArray,
        callbackContext: CallbackContext
    ): Boolean {
        Log.d(TAG, "Executing action: $action")
        return when (action) {
            "echo" -> {
                val message = args.optString(0, "")
                this.echo(message, callbackContext)
                true
            }
            "echoAsync" -> {
                val message = args.optString(0, "")
                this.echoAsync(message, callbackContext)
                true
            }
            "add" -> {
                val num1 = args.optDouble(0, Double.NaN)
                val num2 = args.optDouble(1, Double.NaN)
                this.add(num1, num2, callbackContext)
                true
            }
            "checkClerk" -> {
                val publishableKey = args.optString(0, "")
                this.checkClerk(publishableKey, callbackContext)
                true
            }
            "initializeClerk" -> {
                val publishableKey = args.optString(0, "")
                this.initializeClerk(publishableKey, callbackContext)
                true
            }
            else -> false
        }
    }

    private fun echo(message: String?, callbackContext: CallbackContext) {
        if (!message.isNullOrEmpty()) {
            callbackContext.success(message)
        } else {
            callbackContext.error("Expected one non-empty string argument.")
        }
    }

    private fun echoAsync(message: String?, callbackContext: CallbackContext) {
        cordova.threadPool.execute {
            if (!message.isNullOrEmpty()) {
                val response = JSONObject().apply {
                    put("status", "success")
                    put("message", message)
                    put("timestamp", System.currentTimeMillis())
                    put("language", "Kotlin")
                }
                callbackContext.success(response)
            } else {
                callbackContext.error("Expected one non-empty string argument.")
            }
        }
    }

    private fun add(num1: Double, num2: Double, callbackContext: CallbackContext) {
        if (num1.isNaN() || num2.isNaN()) {
            callbackContext.error("Expected two valid numeric arguments.")
        } else {
            val sum = num1 + num2
            val response = JSONObject().apply {
                put("num1", num1)
                put("num2", num2)
                put("sum", sum)
            }
            callbackContext.success(response)
        }
    }

    /**
     * Check Clerk Android SDK availability on classpath and test initialization.
     */
    private fun checkClerk(publishableKey: String?, callbackContext: CallbackContext) {
        cordova.threadPool.execute {
            val response = JSONObject()
            try {
                // Verify Clerk SDK availability on classpath
                val clerkClass = Class.forName("com.clerk.api.Clerk")
                response.put("sdkAvailable", true)
                response.put("className", clerkClass.name)

                if (!publishableKey.isNullOrEmpty()) {
                    try {
                        val context = cordova.activity.applicationContext
                        Clerk.initialize(context, publishableKey)
                        response.put("initialized", true)
                        response.put("publishableKey", publishableKey)
                        response.put("message", "Clerk SDK is present and successfully initialized.")
                    } catch (e: Exception) {
                        response.put("initialized", false)
                        response.put("error", e.message ?: e.toString())
                        response.put("message", "Clerk SDK found, but initialization failed: ${e.message}")
                    }
                } else {
                    response.put("initialized", false)
                    response.put("message", "Clerk SDK is present on Android classpath. Pass a publishableKey to initialize.")
                }

                response.put("status", "success")
                response.put("platform", "android")
                response.put("timestamp", System.currentTimeMillis())
                callbackContext.success(response)
            } catch (e: ClassNotFoundException) {
                response.put("sdkAvailable", false)
                response.put("status", "error")
                response.put("message", "Clerk SDK (com.clerk.api.Clerk) was not found on the Android classpath.")
                response.put("platform", "android")
                response.put("timestamp", System.currentTimeMillis())
                callbackContext.error(response)
            } catch (e: Throwable) {
                response.put("sdkAvailable", false)
                response.put("status", "error")
                response.put("message", "Error testing Clerk SDK: ${e.message}")
                response.put("platform", "android")
                response.put("timestamp", System.currentTimeMillis())
                callbackContext.error(response)
            }
        }
    }

    /**
     * Explicitly initialize Clerk Android SDK with a Publishable Key.
     */
    private fun initializeClerk(publishableKey: String?, callbackContext: CallbackContext) {
        if (publishableKey.isNullOrEmpty()) {
            callbackContext.error("Expected a non-empty publishableKey string argument.")
            return
        }
        cordova.threadPool.execute {
            try {
                val context = cordova.activity.applicationContext
                Clerk.initialize(context, publishableKey)
                val response = JSONObject().apply {
                    put("status", "success")
                    put("message", "Clerk SDK initialized successfully.")
                    put("publishableKey", publishableKey)
                    put("platform", "android")
                    put("timestamp", System.currentTimeMillis())
                }
                callbackContext.success(response)
            } catch (e: Throwable) {
                val response = JSONObject().apply {
                    put("status", "error")
                    put("message", "Failed to initialize Clerk SDK: ${e.message}")
                    put("error", e.toString())
                    put("platform", "android")
                    put("timestamp", System.currentTimeMillis())
                }
                callbackContext.error(response)
            }
        }
    }
}
