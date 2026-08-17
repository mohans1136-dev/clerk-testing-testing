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
            "signInWithPassword" -> {
                val identifier = args.optString(0, "")
                val password = args.optString(1, "")
                this.signInWithPassword(identifier, password, callbackContext)
                true
            }
            "signOut" -> {
                this.signOut(callbackContext)
                true
            }
            "getCurrentUser" -> {
                this.getCurrentUser(callbackContext)
                true
            }
            else -> false
        }
    }

    private fun echo(message: String?, callbackContext: CallbackContext) {
        val msg = message ?: ""
        if (msg.isNotEmpty()) {
            callbackContext.success(msg)
        } else {
            callbackContext.error("Expected one non-empty string argument.")
        }
    }

    private fun echoAsync(message: String?, callbackContext: CallbackContext) {
        cordova.threadPool.execute {
            val msg = message ?: ""
            if (msg.isNotEmpty()) {
                val response = JSONObject()
                response.put("status", "success")
                response.put("message", msg)
                response.put("timestamp", System.currentTimeMillis())
                response.put("language", "Kotlin")
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
            val response = JSONObject()
            response.put("num1", num1)
            response.put("num2", num2)
            response.put("sum", sum)
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

                val key = publishableKey ?: ""
                if (key.isNotEmpty()) {
                    try {
                        val context = cordova.activity.applicationContext
                        Clerk.initialize(context, key)
                        response.put("initialized", true)
                        response.put("publishableKey", key)
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
        val key = publishableKey ?: ""
        if (key.isEmpty()) {
            callbackContext.error("Expected a non-empty publishableKey string argument.")
            return
        }
        cordova.threadPool.execute {
            try {
                val context = cordova.activity.applicationContext
                Clerk.initialize(context, key)
                val response = JSONObject()
                response.put("status", "success")
                response.put("message", "Clerk SDK initialized successfully.")
                response.put("publishableKey", key)
                response.put("platform", "android")
                response.put("timestamp", System.currentTimeMillis())
                callbackContext.success(response)
            } catch (e: Throwable) {
                val response = JSONObject()
                response.put("status", "error")
                response.put("message", "Failed to initialize Clerk SDK: ${e.message}")
                response.put("error", e.toString())
                response.put("platform", "android")
                response.put("timestamp", System.currentTimeMillis())
                callbackContext.error(response)
            }
        }
    }

    /**
     * Sign in a user with identifier and password via Clerk SDK.
     */
    private fun signInWithPassword(identifier: String?, password: String?, callbackContext: CallbackContext) {
        val id = identifier ?: ""
        val pass = password ?: ""
        if (id.isEmpty() || pass.isEmpty()) {
            callbackContext.error("Expected non-empty identifier and password arguments.")
            return
        }

        cordova.threadPool.execute {
            try {
                val response = JSONObject()
                kotlinx.coroutines.runBlocking {
                    val result = Clerk.auth.signInWithPassword {
                        this.identifier = id
                        this.password = pass
                    }
                    when (result) {
                        is com.clerk.api.network.serialization.ClerkResult.Success -> {
                            val signInData = result.value
                            response.put("status", "success")
                            response.put("message", "Sign in successful")
                            response.put("identifier", id)
                            response.put("signInId", signInData.id)
                            response.put("signInStatus", signInData.status.name)
                            response.put("createdSessionId", signInData.createdSessionId)
                            callbackContext.success(response)
                        }
                        is com.clerk.api.network.serialization.ClerkResult.Failure -> {
                            val err = result.throwable?.message ?: result.toString()
                            response.put("status", "error")
                            response.put("message", "Sign in failed: $err")
                            response.put("error", err)
                            callbackContext.error(response)
                        }
                    }
                }
            } catch (e: Throwable) {
                val response = JSONObject()
                response.put("status", "error")
                response.put("message", "Exception during sign in: ${e.message}")
                response.put("error", e.toString())
                callbackContext.error(response)
            }
        }
    }

    /**
     * Sign out active user session via Clerk SDK.
     */
    private fun signOut(callbackContext: CallbackContext) {
        cordova.threadPool.execute {
            try {
                val response = JSONObject()
                kotlinx.coroutines.runBlocking {
                    val result = Clerk.auth.signOut()
                    when (result) {
                        is com.clerk.api.network.serialization.ClerkResult.Success -> {
                            response.put("status", "success")
                            response.put("message", "Signed out successfully")
                            callbackContext.success(response)
                        }
                        is com.clerk.api.network.serialization.ClerkResult.Failure -> {
                            val err = result.throwable?.message ?: result.toString()
                            response.put("status", "error")
                            response.put("message", "Sign out failed: $err")
                            response.put("error", err)
                            callbackContext.error(response)
                        }
                    }
                }
            } catch (e: Throwable) {
                val response = JSONObject()
                response.put("status", "error")
                response.put("message", "Exception during sign out: ${e.message}")
                response.put("error", e.toString())
                callbackContext.error(response)
            }
        }
    }

    /**
     * Query current active user session status via Clerk SDK.
     */
    private fun getCurrentUser(callbackContext: CallbackContext) {
        cordova.threadPool.execute {
            val response = JSONObject()
            try {
                val sessions = Clerk.auth.sessions
                if (sessions.isNotEmpty()) {
                    val activeSession = sessions.first()
                    response.put("status", "success")
                    response.put("isSignedIn", true)
                    response.put("sessionId", activeSession.id)
                    response.put("userId", activeSession.userId)
                    callbackContext.success(response)
                } else {
                    response.put("status", "success")
                    response.put("isSignedIn", false)
                    response.put("message", "No active signed-in user session found.")
                    callbackContext.success(response)
                }
            } catch (e: Throwable) {
                response.put("status", "error")
                response.put("message", "Failed to retrieve current user status: ${e.message}")
                response.put("error", e.toString())
                callbackContext.error(response)
            }
        }
    }
}
