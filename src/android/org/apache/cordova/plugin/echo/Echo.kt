package org.apache.cordova.plugin.echo

import org.apache.cordova.CordovaPlugin
import org.apache.cordova.CallbackContext
import org.json.JSONArray
import org.json.JSONObject
import android.util.Log
import com.clerk.api.Clerk
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull
import java.net.HttpURLConnection
import java.net.URL

/**
 * Echo Cordova Plugin implemented in Kotlin with Clerk Android SDK Integration.
 */
class Echo : CordovaPlugin() {

    companion object {
        private const val TAG = "EchoPlugin"
        private const val NETWORK_TIMEOUT_MS = 15000L
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
            "testConnection" -> {
                val publishableKey = args.optString(0, "")
                this.testConnection(publishableKey, callbackContext)
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
                Log.d(TAG, "checkClerk called")
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
                        Log.d(TAG, "Clerk SDK initialized via checkClerk")
                    } catch (e: Exception) {
                        Log.e(TAG, "Initialization failed in checkClerk", e)
                        response.put("initialized", false)
                        response.put("error", e.message ?: e.toString())
                        response.put("message", "Clerk SDK found, but initialization failed: ${e.message}")
                    }
                } else {
                    val isInit = try { Clerk.isInitialized } catch (t: Throwable) { false }
                    response.put("initialized", isInit)
                    response.put("message", "Clerk SDK is present on Android classpath.")
                }

                response.put("status", "success")
                response.put("platform", "android")
                response.put("timestamp", System.currentTimeMillis())
                callbackContext.success(response)
            } catch (e: ClassNotFoundException) {
                Log.e(TAG, "Clerk SDK class not found", e)
                response.put("sdkAvailable", false)
                response.put("status", "error")
                response.put("message", "Clerk SDK (com.clerk.api.Clerk) was not found on the Android classpath.")
                response.put("platform", "android")
                response.put("timestamp", System.currentTimeMillis())
                callbackContext.error(response)
            } catch (e: Throwable) {
                Log.e(TAG, "Error in checkClerk", e)
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
                Log.d(TAG, "initializeClerk called with key length ${key.length}")
                val context = cordova.activity.applicationContext
                Clerk.initialize(context, key)
                val response = JSONObject()
                response.put("status", "success")
                response.put("message", "Clerk SDK initialized successfully.")
                response.put("publishableKey", key)
                response.put("platform", "android")
                response.put("timestamp", System.currentTimeMillis())
                Log.d(TAG, "initializeClerk success")
                callbackContext.success(response)
            } catch (e: Throwable) {
                Log.e(TAG, "initializeClerk failed", e)
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
     * Diagnostic test pipeline verifying SDK state, network connectivity, and publishable key.
     */
    private fun testConnection(publishableKey: String?, callbackContext: CallbackContext) {
        cordova.threadPool.execute {
            val response = JSONObject()
            val diagnostics = JSONObject()
            try {
                Log.d(TAG, "testConnection pipeline started")

                // 1. SDK Class Check
                val clerkClass = Class.forName("com.clerk.api.Clerk")
                diagnostics.put("sdkAvailable", true)
                diagnostics.put("sdkClass", clerkClass.name)

                // 2. Auto-initialize if key provided
                val key = publishableKey ?: ""
                if (key.isNotEmpty()) {
                    try {
                        val context = cordova.activity.applicationContext
                        Clerk.initialize(context, key)
                        diagnostics.put("initialized", true)
                    } catch (e: Throwable) {
                        diagnostics.put("initialized", false)
                        diagnostics.put("initError", e.message ?: e.toString())
                    }
                }

                val isInit = try { Clerk.isInitialized } catch (t: Throwable) { false }
                diagnostics.put("isSDKInitialized", isInit)

                // 3. Network Ping Test to Clerk Server
                var networkReachable = false
                var responseCode = -1
                try {
                    val url = URL("https://api.clerk.com/v1/environment")
                    val connection = url.openConnection() as HttpURLConnection
                    connection.requestMethod = "GET"
                    connection.connectTimeout = 5000
                    connection.readTimeout = 5000
                    if (key.isNotEmpty()) {
                        connection.setRequestProperty("Authorization", "Bearer $key")
                    }
                    connection.connect()
                    responseCode = connection.responseCode
                    networkReachable = (responseCode > 0)
                    connection.disconnect()
                } catch (netEx: Throwable) {
                    Log.w(TAG, "Network ping failed: ${netEx.message}")
                    diagnostics.put("networkError", netEx.message ?: netEx.toString())
                }

                diagnostics.put("networkReachable", networkReachable)
                diagnostics.put("httpResponseCode", responseCode)

                response.put("status", if (networkReachable && isInit) "success" else "warning")
                response.put("message", "Connection diagnostic pipeline executed.")
                response.put("diagnostics", diagnostics)
                response.put("timestamp", System.currentTimeMillis())

                Log.d(TAG, "testConnection pipeline result: $response")
                callbackContext.success(response)
            } catch (e: Throwable) {
                Log.e(TAG, "testConnection pipeline exception", e)
                response.put("status", "error")
                response.put("message", "Diagnostic pipeline failed: ${e.message}")
                response.put("error", e.toString())
                response.put("diagnostics", diagnostics)
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
            Log.w(TAG, "signInWithPassword called with empty arguments")
            callbackContext.error("Expected non-empty identifier and password arguments.")
            return
        }

        cordova.threadPool.execute {
            Log.d(TAG, "signInWithPassword execution started for identifier: $id")
            val response = JSONObject()

            // Pre-check SDK initialization state
            val isInit = try { Clerk.isInitialized } catch (t: Throwable) { false }
            if (!isInit) {
                Log.e(TAG, "signInWithPassword failed: Clerk SDK is not initialized")
                response.put("status", "error")
                response.put("message", "Clerk SDK is not initialized. Please call initializeClerk(publishableKey) first.")
                callbackContext.error(response)
                return@execute
            }

            try {
                runBlocking(Dispatchers.IO) {
                    val result = withTimeoutOrNull(NETWORK_TIMEOUT_MS) {
                        Clerk.auth.signInWithPassword {
                            this.identifier = id
                            this.password = pass
                        }
                    }

                    if (result == null) {
                        Log.e(TAG, "signInWithPassword timed out after ${NETWORK_TIMEOUT_MS}ms")
                        response.put("status", "error")
                        response.put("message", "Sign in request timed out after ${NETWORK_TIMEOUT_MS / 1000} seconds. Please check your network connection.")
                        callbackContext.error(response)
                        return@runBlocking
                    }

                    when (result) {
                        is com.clerk.api.network.serialization.ClerkResult.Success -> {
                            val signInData = result.value
                            Log.d(TAG, "signInWithPassword SUCCESS: signInId=${signInData.id}, status=${signInData.status.name}")
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
                            Log.e(TAG, "signInWithPassword FAILURE: $err")
                            response.put("status", "error")
                            response.put("message", "Sign in failed: $err")
                            response.put("error", err)
                            callbackContext.error(response)
                        }
                    }
                }
            } catch (e: Throwable) {
                Log.e(TAG, "signInWithPassword Exception caught", e)
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
            Log.d(TAG, "signOut execution started")
            val response = JSONObject()

            val isInit = try { Clerk.isInitialized } catch (t: Throwable) { false }
            if (!isInit) {
                Log.e(TAG, "signOut failed: Clerk SDK is not initialized")
                response.put("status", "error")
                response.put("message", "Clerk SDK is not initialized.")
                callbackContext.error(response)
                return@execute
            }

            try {
                runBlocking(Dispatchers.IO) {
                    val result = withTimeoutOrNull(NETWORK_TIMEOUT_MS) {
                        Clerk.auth.signOut()
                    }

                    if (result == null) {
                        Log.e(TAG, "signOut timed out after ${NETWORK_TIMEOUT_MS}ms")
                        response.put("status", "error")
                        response.put("message", "Sign out request timed out.")
                        callbackContext.error(response)
                        return@runBlocking
                    }

                    when (result) {
                        is com.clerk.api.network.serialization.ClerkResult.Success -> {
                            Log.d(TAG, "signOut SUCCESS")
                            response.put("status", "success")
                            response.put("message", "Signed out successfully")
                            callbackContext.success(response)
                        }
                        is com.clerk.api.network.serialization.ClerkResult.Failure -> {
                            val err = result.throwable?.message ?: result.toString()
                            Log.e(TAG, "signOut FAILURE: $err")
                            response.put("status", "error")
                            response.put("message", "Sign out failed: $err")
                            response.put("error", err)
                            callbackContext.error(response)
                        }
                    }
                }
            } catch (e: Throwable) {
                Log.e(TAG, "signOut Exception caught", e)
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
            Log.d(TAG, "getCurrentUser execution started")
            val response = JSONObject()
            try {
                val isInit = try { Clerk.isInitialized } catch (t: Throwable) { false }
                if (!isInit) {
                    response.put("status", "success")
                    response.put("isSignedIn", false)
                    response.put("message", "Clerk SDK is not initialized.")
                    callbackContext.success(response)
                    return@execute
                }

                val sessions = Clerk.auth.sessions
                if (sessions.isNotEmpty()) {
                    val activeSession = sessions.first()
                    val user = activeSession.user
                    Log.d(TAG, "getCurrentUser: active session found ID=${activeSession.id}")
                    response.put("status", "success")
                    response.put("isSignedIn", true)
                    response.put("sessionId", activeSession.id)
                    response.put("userId", user?.id ?: "")
                    response.put("firstName", user?.firstName ?: "")
                    response.put("lastName", user?.lastName ?: "")
                    callbackContext.success(response)
                } else {
                    Log.d(TAG, "getCurrentUser: no active sessions")
                    response.put("status", "success")
                    response.put("isSignedIn", false)
                    response.put("message", "No active signed-in user session found.")
                    callbackContext.success(response)
                }
            } catch (e: Throwable) {
                Log.e(TAG, "getCurrentUser Exception caught", e)
                response.put("status", "error")
                response.put("message", "Failed to retrieve current user status: ${e.message}")
                response.put("error", e.toString())
                callbackContext.error(response)
            }
        }
    }
}
