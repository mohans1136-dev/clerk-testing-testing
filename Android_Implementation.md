# Android Clerk Plugin Implementation & Sequence Architecture

This document provides a comprehensive technical breakdown of how the **Android Clerk Plugin** is structured, initialized, and executed within the hybrid Apache Cordova and OutSystems MABS (Mobile App Build Service) environment.

---

## 🏛️ Architecture Overview

The plugin bridges the web layer (JavaScript in the Cordova WebView) to the native Android environment via Cordova's native messaging bridge (`cordova.exec`), delegating asynchronous and network operations to background thread pools and Kotlin coroutines.

```
┌────────────────────────────────────────────────────────┐
│             Cordova WebView / JavaScript               │
│          (window.echo / cordova.plugins.echo)          │
└──────────────────────────┬─────────────────────────────┘
                           │ cordova.exec(...)
┌──────────────────────────▼─────────────────────────────┐
│          Cordova Android Plugin (Echo.kt)              │
│       - Action routing via execute()                   │
│       - Thread dispatch (cordova.threadPool)           │
│       - Coroutine IO dispatch (Dispatchers.IO)         │
│       - Timeout management (15000ms)                   │
│       - Reflection-based error extraction              │
└──────────────────────────┬─────────────────────────────┘
                           │
┌──────────────────────────▼─────────────────────────────┐
│          Clerk Android SDK (com.clerk.api)             │
│       - Clerk.initialize()                             │
│       - Clerk.auth.startHostedAuth() [OIDC / SSO]      │
│       - Clerk.auth.signInWithPassword()                │
│       - Clerk.auth.setActive()                         │
│       - Clerk.auth.signOut()                           │
│       - Clerk.reloadFromSharedStorage()                │
└──────────────────────────┬─────────────────────────────┘
                           │ HTTPS / TLS
┌──────────────────────────▼─────────────────────────────┐
│               Clerk Cloud Backend API                  │
│               (https://api.clerk.com)                  │
└────────────────────────────────────────────────────────┘
```

---

## 📊 Complete Sequence Diagrams

### 1. Initialization & SDK Verification (`initializeClerk` & `checkClerk`)

```mermaid
sequenceDiagram
    autonumber
    actor App as Hybrid App / OutSystems (JS)
    participant JS as echo.js (Bridge)
    participant Exec as cordova.exec
    participant Native as Echo.kt (Android Plugin)
    participant Pool as cordova.threadPool
    participant ClerkSDK as Clerk Android SDK
    
    App->>JS: initializeClerk(publishableKey, enableSharedSessionSync)
    JS->>JS: Validate publishableKey is non-empty string
    alt Key is empty
        JS-->>App: errorCallback("Expected a non-empty publishableKey...")
    else Valid key
        JS->>Exec: exec(success, error, "Echo", "initializeClerk", [key, syncEnabled])
        Exec->>Native: execute("initializeClerk", args, callbackContext)
        Native->>Pool: cordova.threadPool.execute { ... }
        
        activate Pool
        Pool->>Pool: Configure ClerkConfigurationOptions(sharedSessionSync)
        Pool->>ClerkSDK: Clerk.initialize(context, publishableKey, options)
        
        alt Initialization Successful
            ClerkSDK-->>Pool: Ready
            Pool-->>Native: JSON { status: "success", publishableKey, sharedSessionSyncEnabled: true }
            Native-->>Exec: callbackContext.success(response)
            Exec-->>JS: fire successCallback
            JS-->>App: Return success JSON
        else Exception Thrown
            ClerkSDK-->>Pool: Error / Exception
            Pool-->>Native: JSON { status: "error", message, error }
            Native-->>Exec: callbackContext.error(response)
            Exec-->>JS: fire errorCallback
            JS-->>App: Return error JSON
        end
        deactivate Pool
    end
```

---

### 2. Hosted Authentication Flow (`startHostedAuth` - Microsoft Enterprise SSO / Account Portal)

```mermaid
sequenceDiagram
    autonumber
    actor User
    actor App as Hybrid App / OutSystems UI
    participant JS as echo.js
    participant Native as Echo.kt
    participant Pool as Cordova ThreadPool
    participant Coroutine as Dispatchers.IO (runBlocking)
    participant ClerkSDK as Clerk.auth
    participant CustomTab as In-App Custom Tab
    participant ClerkPortal as Clerk Account Portal
    participant Microsoft as Microsoft Entra ID (Azure AD)
    participant Storage as Android Shared Storage

    App->>JS: startHostedAuth({ mode: 'sign_in' })
    JS->>Native: exec("Echo", "startHostedAuth", [mode])
    Native->>Pool: execute { ... }
    
    activate Pool
    Pool->>Pool: Verify Clerk.isInitialized
    Pool->>Coroutine: runBlocking(Dispatchers.IO)
    activate Coroutine
    
    Coroutine->>ClerkSDK: Clerk.auth.startHostedAuth(mode)
    activate ClerkSDK
    ClerkSDK->>CustomTab: Launch in-app Custom Tab overlay
    CustomTab->>ClerkPortal: Load Account Portal
    
    opt Microsoft Enterprise SSO
        User->>CustomTab: Click "Sign in with Microsoft"
        CustomTab->>Microsoft: Azure AD OAuth Flow & Conditional Access
        Microsoft-->>CustomTab: OAuth Callback to Clerk
    end
    
    ClerkPortal-->>ClerkSDK: Deep link return with Auth Ticket
    ClerkSDK->>CustomTab: Dismiss browser overlay automatically
    ClerkSDK->>ClerkSDK: Set active session & refresh tokens
    ClerkSDK->>Storage: Persist session to shared storage (SharedSessionSyncConfig)
    ClerkSDK-->>Coroutine: ClerkResult.Success(Session)
    deactivate ClerkSDK
    
    alt Success
        Coroutine-->>Pool: Session details (sessionId, userId, names, email)
        Pool-->>Native: JSON { status: "success", sessionId, userId, firstName, lastName, email }
        Native-->>JS: callbackContext.success(response)
        JS-->>App: Return user session payload
    else User Cancelled (Closed Browser)
        ClerkSDK-->>Coroutine: Cancellation Exception / Error
        Coroutine-->>Pool: Cancellation detected
        Pool-->>Native: JSON { status: "cancelled", message: "User cancelled authentication" }
        Native-->>JS: callbackContext.error(response)
        JS-->>App: Handle cancellation
    else Error
        Coroutine-->>Pool: Error message & code
        Pool-->>Native: JSON { status: "error", message, errorCode }
        Native-->>JS: callbackContext.error(response)
        JS-->>App: Handle error
    end
    deactivate Coroutine
    deactivate Pool
```

---

### 3. User Authentication Flow (`signInWithPassword` & `setActive`)

```mermaid
sequenceDiagram
    autonumber
    actor App as Hybrid App UI
    participant JS as echo.js
    participant Native as Echo.kt
    participant Pool as Cordova ThreadPool
    participant Coroutine as Dispatchers.IO (runBlocking)
    participant ClerkSDK as Clerk.auth
    participant ClerkAPI as Clerk Backend API (Cloud)

    App->>JS: signInWithPassword(identifier, password)
    JS->>Native: exec("Echo", "signInWithPassword", [identifier, password])
    Native->>Pool: execute { ... }
    
    activate Pool
    Pool->>Pool: Check Clerk.isInitialized.value
    alt SDK Not Initialized
        Pool-->>Native: JSON { status: "error", message: "Clerk SDK is not initialized..." }
        Native-->>JS: callbackContext.error(response)
        JS-->>App: errorCallback(error)
    else SDK is Initialized
        Pool->>Coroutine: runBlocking(Dispatchers.IO) withTimeout(15000ms)
        activate Coroutine
        
        Coroutine->>ClerkSDK: Clerk.auth.signInWithPassword { id, password }
        activate ClerkSDK
        ClerkSDK->>ClerkAPI: POST /v1/client/sign_ins
        ClerkAPI-->>ClerkSDK: 200 OK / HTTP Error Response
        ClerkSDK-->>Coroutine: ClerkResult (Success or Failure)
        deactivate ClerkSDK
        
        alt ClerkResult.Success
            Coroutine->>ClerkSDK: Clerk.auth.setActive(sessionId = createdSessionId)
            ClerkSDK-->>Coroutine: Session activated
            Coroutine-->>Pool: Success Data (signInId, signInStatus, createdSessionId)
            Pool-->>Native: JSON { status: "success", signInId, signInStatus, createdSessionId }
            Native-->>JS: callbackContext.success(response)
            JS-->>App: successCallback(response)
        else ClerkResult.Failure
            Coroutine->>Coroutine: extractClerkError(failure)
            Coroutine-->>Pool: Error message & code
            Pool-->>Native: JSON { status: "error", message, errorCode, error }
            Native-->>JS: callbackContext.error(response)
            JS-->>App: errorCallback(response)
        else Timeout (>15s)
            Coroutine-->>Pool: null
            Pool-->>Native: JSON { status: "error", message: "Sign in request timed out..." }
            Native-->>JS: callbackContext.error(response)
            JS-->>App: errorCallback(response)
        end
        deactivate Coroutine
    end
    deactivate Pool
```

---

### 3. Session Query, Shared Storage Sync & Sign-Out

```mermaid
sequenceDiagram
    autonumber
    actor App as Hybrid App
    participant JS as echo.js
    participant Native as Echo.kt
    participant Pool as ThreadPool / Coroutines
    participant ClerkSDK as Clerk SDK (Local Cache & API)
    participant ClerkAPI as Clerk Cloud Backend

    %% GET CURRENT USER
    rect rgb(240, 248, 255)
        Note over App,ClerkAPI: Action: getCurrentUser
        App->>JS: getCurrentUser()
        JS->>Native: exec("Echo", "getCurrentUser", [])
        Native->>Pool: Check Clerk.auth.sessions
        alt Active Session Exists
            Pool->>ClerkSDK: Read session & user details
            ClerkSDK-->>Pool: activeSession.user (id, firstName, lastName)
            Pool-->>Native: JSON { status: "success", isSignedIn: true, sessionId, userId, firstName, lastName }
            Native-->>JS: callbackContext.success(response)
            JS-->>App: successCallback(userData)
        else No Active Session
            Pool-->>Native: JSON { status: "success", isSignedIn: false, message: "No active session..." }
            Native-->>JS: callbackContext.success(response)
            JS-->>App: successCallback({ isSignedIn: false })
        end
    end

    %% RELOAD SHARED STORAGE
    rect rgb(245, 255, 245)
        Note over App,ClerkAPI: Action: reloadFromSharedStorage (Sibling App Sync)
        App->>JS: reloadFromSharedStorage()
        JS->>Native: exec("Echo", "reloadFromSharedStorage", [])
        Native->>Pool: runBlocking(Dispatchers.IO) { Clerk.reloadFromSharedStorage() }
        Pool->>ClerkSDK: Reload tokens & session state from shared Android secure storage
        ClerkSDK-->>Pool: stateChanged (boolean)
        Pool-->>Native: JSON { status: "success", stateChanged: boolean }
        Native-->>JS: callbackContext.success(response)
        JS-->>App: successCallback(result)
    end

    %% SIGN OUT
    rect rgb(255, 245, 245)
        Note over App,ClerkAPI: Action: signOut
        App->>JS: signOut()
        JS->>Native: exec("Echo", "signOut", [])
        Native->>Pool: runBlocking(Dispatchers.IO) withTimeout(15000ms)
        Pool->>ClerkSDK: Clerk.auth.signOut()
        ClerkSDK->>ClerkAPI: Invalidate Client Session
        ClerkAPI-->>ClerkSDK: Invalidation confirmed
        ClerkSDK-->>Pool: ClerkResult.Success
        Pool-->>Native: JSON { status: "success", message: "Signed out successfully" }
        Native-->>JS: callbackContext.success(response)
        JS-->>App: successCallback(result)
    end
```

---

### 4. Connection & Environment Diagnostic Pipeline (`testConnection`)

```mermaid
sequenceDiagram
    autonumber
    actor App as Hybrid App
    participant JS as echo.js
    participant Native as Echo.kt
    participant Pool as cordova.threadPool
    participant ClerkSDK as Clerk Class & Options
    participant Http as HttpURLConnection
    participant ClerkAPI as https://api.clerk.com/v1/environment

    App->>JS: testConnection(publishableKey)
    JS->>Native: exec("Echo", "testConnection", [publishableKey])
    Native->>Pool: execute { ... }
    
    activate Pool
    Pool->>Pool: Check Class.forName("com.clerk.api.Clerk")
    Pool->>ClerkSDK: Initialize SDK if key provided
    Pool->>Pool: Verify Clerk.isInitialized.value
    
    Pool->>Http: Open URL("https://api.clerk.com/v1/environment")
    Http->>ClerkAPI: GET with Authorization Bearer <key> (5s timeout)
    ClerkAPI-->>Http: HTTP Response Code (e.g. 200)
    Http-->>Pool: responseCode & networkReachable = true
    
    Pool-->>Native: JSON { status: "success", diagnostics: { sdkAvailable: true, isSDKInitialized: true, networkReachable: true, httpResponseCode: 200 } }
    Native-->>JS: callbackContext.success(response)
    JS-->>App: successCallback(diagnosticResult)
    deactivate Pool
```

---

## 🔧 Core Implementation Details in `Echo.kt`

### 1. Thread Safety & Asynchronous Dispatch
All actions that perform network or disk I/O are executed on Cordova's background thread pool via `cordova.threadPool.execute { ... }` to prevent UI thread blocking.

### 2. Coroutine Bridging (`runBlocking` & `withTimeoutOrNull`)
Since the Clerk Android SDK exposes suspending Kotlin coroutines (`suspend fun`), the plugin utilizes:
```kotlin
runBlocking(Dispatchers.IO) {
    val result = withTimeoutOrNull(NETWORK_TIMEOUT_MS) {
        Clerk.auth.signInWithPassword {
            this.identifier = id
            this.password = pass
        }
    }
    // Handle result or timeout
}
```
A default timeout of `15000L` (15 seconds) protects the app against hanging on unstable mobile networks.

### 3. Reflection-Based Error Extraction (`extractClerkError`)
Clerk SDK failure structures (`ClerkResult.Failure`) encapsulate error details inside private/internal models. The `extractClerkError` helper inspects fields dynamically (`errors`, `longMessage`, `message`, `code`) to return clean, actionable error strings back to OutSystems/Cordova:
```kotlin
private fun extractClerkError(failure: com.clerk.api.network.serialization.ClerkResult.Failure<*>): Pair<String, String>
```

### 4. Shared Session Sync Configuration
Single Sign-On across sibling apps on Android is enabled during initialization:
```kotlin
val options = ClerkConfigurationOptions(
    sharedSessionSync = if (enableSharedSessionSync) SharedSessionSyncConfig.enabled else null
)
Clerk.initialize(context = context, publishableKey = key, options = options)
```

---

## 📦 Gradle & Build Configuration

- **SDK Dependency**: `com.clerk:clerk-android-api:1.1.1` configured in `plugin.xml`.
- **Kotlin Version**: Configured for Kotlin `2.0.21` with official code style.
- **Build Extras**: `src/android/build-extras.gradle` configures `-Xskip-metadata-version-check` to ensure compatibility across different Kotlin runtime versions in OutSystems MABS builds.
