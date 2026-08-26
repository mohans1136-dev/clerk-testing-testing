# Clerk Authentication & Shared Session Implementation Guide (`cordova-plugin-echo`)

This document provides a comprehensive technical overview, implementation architecture, and complete sequence diagrams for the Clerk Cordova plugin (`cordova-plugin-echo`).

---

## 📑 Table of Contents

1. [Architectural Overview](#1-architectural-overview)
2. [Component Structure & Responsibilities](#2-component-structure--responsibilities)
3. [Platform-Specific Implementations](#3-platform-specific-implementations)
   - [Android: Kotlin Engine & Clerk Android SDK](#android-kotlin-engine--clerk-android-sdk)
   - [iOS: Swift REST Engine & Shared Keychain Access Group](#ios-swift-rest-engine--shared-keychain-access-group)
4. [Complete Sequence Diagrams](#4-complete-sequence-diagrams)
   - [1. High-Level Architecture Diagram](#1-high-level-architecture-diagram)
   - [2. Initialization Flow (`initializeClerk`)](#2-initialization-flow-initializeclerk)
   - [3. Sign In Flow (`signInWithPassword`)](#3-sign-in-flow-signinwithpassword)
   - [4. Query Active Session & Live Profile Refresh (`getCurrentUser`)](#4-query-active-session--live-profile-refresh-getcurrentuser)
   - [5. Cross-App Single Sign-On (SSO) Flow (`reloadFromSharedStorage`)](#5-cross-app-single-sign-on-sso-flow-reloadfromsharedstorage)
   - [6. Sign Out Flow (`signOut`)](#6-sign-out-flow-signout)
   - [7. Diagnostics & Connectivity Flow (`testConnection` / `checkClerk`)](#7-diagnostics--connectivity-flow-testconnection--checkclerk)
5. [Auto-Healing on iOS (`dev_browser_unauthenticated`)](#5-auto-healing-on-ios-dev_browser_unauthenticated)
6. [OutSystems MABS Integration & Keychain Entitlements](#6-outsystems-mabs-integration--keychain-entitlements)

---

## 1. Architectural Overview

The plugin bridges hybrid web applications (such as OutSystems Reactive/Mobile or Apache Cordova) to Clerk Authentication services with native performance and cross-app session sharing.

```mermaid
graph TD
    App["OutSystems / Cordova Web Client"] -->|window.echo / cordova.plugins.echo| JS["echo.js (JS Interface)"]
    JS -->|cordova.exec| Bridge["Cordova Native Bridge"]
    Bridge -->|Android Action Dispatch| Kotlin["Echo.kt (Android Kotlin Engine)"]
    Bridge -->|iOS Action Dispatch| Swift["EchoPlugin.swift (iOS Swift Engine)"]
    Kotlin -->|Clerk Android SDK 1.1.1| ClerkBackend["Clerk Cloud Auth Backend"]
    Swift -->|HTTPS REST API (api.clerk.com / FAPI)| ClerkBackend
    Swift -->|SecItemAdd / SecItemCopyMatching| Keychain["iOS Shared Keychain (org.luvelo.dev.shared)"]
    Kotlin -->|SharedSessionSyncConfig| AndroidStorage["Android SDK Shared Storage"]
```

---

## 2. Component Structure & Responsibilities

| File Path | Component | Responsibility |
|---|---|---|
| [`www/echo.js`](file:///d:/Luvelo/Plugins/clerk-testing-testing/www/echo.js) | JavaScript Interface | Exposes standard JavaScript methods on `window.echo` and `cordova.plugins.echo`. Handles argument validation and delegates to `cordova.exec`. |
| [`src/android/org/apache/cordova/plugin/echo/Echo.kt`](file:///d:/Luvelo/Plugins/clerk-testing-testing/src/android/org/apache/cordova/plugin/echo/Echo.kt) | Android Native Engine | Uses official `com.clerk:clerk-android-api:1.1.1` via Kotlin Coroutines. Integrates `SharedSessionSyncConfig.enabled` for cross-app session synchronization. |
| [`src/ios/EchoPlugin.swift`](file:///d:/Luvelo/Plugins/clerk-testing-testing/src/ios/EchoPlugin.swift) | iOS Native Engine | Implements native Clerk Frontend REST API calls, extracts API hosts from publishable keys, stores sessions in shared Keychain Access Groups, and handles automatic recovery from dev browser cookie issues. |
| [`plugin.xml`](file:///d:/Luvelo/Plugins/clerk-testing-testing/plugin.xml) | Plugin Manifest | Configures Android permissions, Gradle Kotlin dependencies, and automatically registers iOS Keychain Access Group entitlements (`$(AppIdentifierPrefix)org.luvelo.dev.shared`) for OutSystems MABS cloud builds. |

---

## 3. Platform-Specific Implementations

### Android: Kotlin Engine & Clerk Android SDK
- **Dependency**: `com.clerk:clerk-android-api:1.1.1`
- **Session Sync**: Configured through `ClerkConfigurationOptions(sharedSessionSync = SharedSessionSyncConfig.enabled)`.
- **Concurrency**: Operations run on background coroutines via `Dispatchers.IO` wrapped in `cordova.threadPool`.
- **Error Handling**: Automatically extracts descriptive messages from `ClerkResult.Failure`.

### iOS: Swift REST Engine & Shared Keychain Access Group
- **Keychain Service**: `com.luvelo.clerk.sharedservice`
- **Keychain Access Group**: `org.luvelo.dev.shared`
- **Frontend API Host Resolution**: Dynamically extracts and decodes the Clerk Frontend API domain from the base64-encoded publishable key (`pk_test_...` or `pk_live_...`).
- **State Storage**:
  - `active_clerk_session_jwt`
  - `active_clerk_session_id`
  - `active_clerk_user_id`
  - `active_clerk_first_name`
  - `active_clerk_last_name`
  - `active_clerk_email`
  - `clerk_publishable_key`
  - `clerk_dev_browser_jwt`

---

## 4. Complete Sequence Diagrams

### 1. High-Level Architecture Diagram

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant App as OutSystems Mobile App
    participant JS as echo.js Bridge
    participant Native as Native Engine (Kotlin / Swift)
    participant Storage as Shared Storage / Keychain
    participant Clerk as Clerk Cloud Backend

    User->>App: Interact with UI (Login, Session Check, Sign Out)
    App->>JS: Call plugin JS method
    JS->>Native: cordova.exec(action, args)
    Native->>Clerk: HTTPS Request / SDK API Call
    Clerk-->>Native: Response (Token, User Info, Status)
    Native->>Storage: Persist session in shared access group
    Native-->>JS: Return formatted JSON result
    JS-->>App: Resolve Promise / Trigger Callback
    App-->>User: Update UI State
```

---

### 2. Initialization Flow (`initializeClerk`)

Initializes the Clerk engine on the native layer and enables cross-application shared session synchronization.

```mermaid
sequenceDiagram
    autonumber
    actor App as Cordova / OutSystems App
    participant JS as echo.js
    participant Bridge as Cordova Bridge (exec)
    participant Android as Echo.kt (Android)
    participant iOS as EchoPlugin.swift (iOS)
    participant Keychain as iOS Shared Keychain
    participant ClerkSDK as Clerk Android SDK

    App->>JS: initializeClerk(publishableKey, enableSharedSessionSync)
    JS->>Bridge: exec('Echo', 'initializeClerk', [publishableKey, syncEnabled])

    alt Android Platform
        Bridge->>Android: execute("initializeClerk", args)
        Android->>ClerkSDK: ClerkConfigurationOptions(sharedSessionSync = enabled)
        Android->>ClerkSDK: Clerk.initialize(context, publishableKey, options)
        ClerkSDK-->>Android: Initialized
        Android-->>Bridge: callbackContext.success({ status: "success", publishableKey, sharedSessionSyncEnabled })
    else iOS Platform
        Bridge->>iOS: initializeClerk(command)
        iOS->>iOS: Cache inMemoryPublishableKey
        iOS->>Keychain: saveToKeychain("clerk_publishable_key", key)
        Keychain-->>iOS: Stored in shared group
        iOS-->>Bridge: CDVPluginResult(status: OK, { status: "success", publishableKey })
    end

    Bridge-->>JS: successCallback(response)
    JS-->>App: Return success status
```

---

### 3. Sign In Flow (`signInWithPassword`)

Authenticates the user with email/username and password, creates the active session, and saves session tokens to shared storage/Keychain.

```mermaid
sequenceDiagram
    autonumber
    actor App as Cordova / OutSystems App
    participant JS as echo.js
    participant Android as Echo.kt (Android)
    participant iOS as EchoPlugin.swift (iOS)
    participant Keychain as iOS Shared Keychain
    participant Cookies as HTTPCookieStorage & WKWebsiteDataStore
    participant ClerkAPI as Clerk Cloud API

    App->>JS: signInWithPassword(identifier, password)
    JS->>JS: Validate non-empty inputs

    alt Android Execution Flow
        JS->>Android: execute("signInWithPassword", [id, pass])
        Android->>Android: Check Clerk.isInitialized
        Android->>ClerkAPI: Clerk.auth.signInWithPassword { identifier, password }
        ClerkAPI-->>Android: ClerkResult.Success(signInData)
        Android->>Android: Clerk.auth.setActive(sessionId = signInData.createdSessionId)
        Android-->>JS: successCallback({ status: "success", signInStatus: "COMPLETE", createdSessionId, identifier })
    else iOS Execution Flow
        JS->>iOS: signInWithPassword(command)
        iOS->>iOS: Extract Frontend API Host from base64 publishableKey
        iOS->>Keychain: loadFromKeychain("clerk_dev_browser_jwt")
        Keychain-->>iOS: dev_browser_jwt (if present)
        iOS->>ClerkAPI: POST https://{host}/v1/client/sign_ins (strategy=password)
        
        alt Success (200 OK)
            ClerkAPI-->>iOS: JSON Response (client, sessions, user)
            iOS->>iOS: extractAndSaveDevBrowserJwt(response)
            iOS->>Keychain: Save session ID, JWT, user ID, names, email
            iOS-->>JS: CDVPluginResult(OK, { status: "success", createdSessionId, userId, firstName, lastName })
        else Error: dev_browser_unauthenticated (Auto-Healing)
            ClerkAPI-->>iOS: Error 401 (dev_browser_unauthenticated)
            iOS->>Keychain: deleteFromKeychain("clerk_dev_browser_jwt")
            iOS->>Cookies: Purge all Clerk cookies & WKWebsiteDataStore
            iOS->>ClerkAPI: Retry POST https://{host}/v1/client/sign_ins (clean state)
            ClerkAPI-->>iOS: JSON Response (client, sessions, user)
            iOS->>Keychain: Save new session tokens & user metadata
            iOS-->>JS: CDVPluginResult(OK, { status: "success", createdSessionId, userId })
        end
    end

    JS-->>App: Resolve Promise / Callback with User & Session Data
```

---

### 4. Query Active Session & Live Profile Refresh (`getCurrentUser`)

Retrieves the currently authenticated user's session metadata and status. On iOS, performs a live revalidation against Clerk.

```mermaid
sequenceDiagram
    autonumber
    actor App as Cordova / OutSystems App
    participant JS as echo.js
    participant Android as Echo.kt (Android)
    participant iOS as EchoPlugin.swift (iOS)
    participant Keychain as iOS Shared Keychain
    participant ClerkAPI as Clerk Cloud API

    App->>JS: getCurrentUser()
    JS->>JS: exec('Echo', 'getCurrentUser', [])

    alt Android Platform
        JS->>Android: execute("getCurrentUser")
        Android->>Android: Query Clerk.auth.sessions
        alt Active Session Exists
            Android-->>JS: successCallback({ isSignedIn: true, sessionId, userId, firstName, lastName })
        else No Session
            Android-->>JS: successCallback({ isSignedIn: false, message: "No active session found" })
        end
    else iOS Platform
        JS->>iOS: getCurrentUser(command)
        iOS->>Keychain: loadFromKeychain (sessionId, userId, firstName, lastName, email)
        Keychain-->>iOS: Cached credentials / tokens
        
        alt Keychain is Empty
            iOS-->>JS: CDVPluginResult(OK, { isSignedIn: false })
        else Active Session in Keychain
            iOS->>ClerkAPI: GET https://{host}/v1/client (Bearer publishableKey) [Timeout: 3.0s]
            alt Live API Succeeded
                ClerkAPI-->>iOS: Updated client / user data
                iOS->>Keychain: Update latest userId, firstName, lastName
                iOS-->>JS: CDVPluginResult(OK, { isSignedIn: true, sessionId, userId, firstName, lastName, email })
            else API Timed Out / Offline
                iOS-->>JS: CDVPluginResult(OK, Cached Keychain data: { isSignedIn: true, sessionId, userId, ... })
            end
        end
    end

    JS-->>App: Return current user session status
```

---

### 5. Cross-App Single Sign-On (SSO) Flow (`reloadFromSharedStorage`)

Demonstrates how two sibling apps share a single login session without re-prompting the user.

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant AppA as App A (e.g., Luvelo Core)
    participant AppB as App B (e.g., Luvelo Driver)
    participant SharedStorage as Shared Keychain / SDK Storage
    participant ClerkAPI as Clerk Cloud Backend

    User->>AppA: 1. Sign In (user@domain.com, password)
    AppA->>ClerkAPI: Authenticate & create session
    ClerkAPI-->>AppA: Session token & user profile
    AppA->>SharedStorage: Store session in Keychain Access Group (org.luvelo.dev.shared)
    AppA-->>User: Logged in successfully

    Note over User,AppB: User opens Sibling Application (App B)

    User->>AppB: 2. Launch App B
    AppB->>AppB: initializeClerk(publishableKey, enableSharedSessionSync=true)
    AppB->>SharedStorage: reloadFromSharedStorage() / getCurrentUser()
    SharedStorage-->>AppB: Read active session token & user info created by App A
    AppB->>ClerkAPI: (Optional) Validate session status
    ClerkAPI-->>AppB: Session valid
    AppB-->>User: Auto Signed In as the same user (SSO)
```

---

### 6. Sign Out Flow (`signOut`)

Revokes the session with the Clerk server, deletes shared Keychain records, and clears all WebKit cookies and data stores.

```mermaid
sequenceDiagram
    autonumber
    actor App as Cordova / OutSystems App
    participant JS as echo.js
    participant Android as Echo.kt (Android)
    participant iOS as EchoPlugin.swift (iOS)
    participant Keychain as iOS Shared Keychain
    participant WebKit as WKWebsiteDataStore & HTTPCookieStorage
    participant ClerkAPI as Clerk Cloud API

    App->>JS: signOut()
    JS->>JS: exec('Echo', 'signOut', [])

    alt Android Platform
        JS->>Android: execute("signOut")
        Android->>ClerkAPI: Clerk.auth.signOut()
        ClerkAPI-->>Android: Success
        Android-->>JS: successCallback({ status: "success", message: "Signed out successfully" })
    else iOS Platform
        JS->>iOS: signOut(command)
        iOS->>Keychain: loadFromKeychain("active_clerk_session_id")
        Keychain-->>iOS: sessionId
        
        opt Session ID exists
            iOS->>ClerkAPI: POST https://{host}/v1/client/sessions/{sessionId}/remove
            ClerkAPI-->>iOS: Session revoked
        end

        iOS->>Keychain: deleteFromKeychain(active_clerk_session_jwt)
        iOS->>Keychain: deleteFromKeychain(active_clerk_session_id)
        iOS->>Keychain: deleteFromKeychain(active_clerk_user_id)
        iOS->>Keychain: deleteFromKeychain(active_clerk_first_name)
        iOS->>Keychain: deleteFromKeychain(active_clerk_last_name)
        iOS->>Keychain: deleteFromKeychain(active_clerk_email)
        
        iOS->>WebKit: purgeAllClerkCookies() (delete HTTP cookies & clear WKWebsiteDataStore)
        
        iOS-->>JS: CDVPluginResult(OK, { status: "success", message: "Signed out successfully" })
    end

    JS-->>App: Callback / Promise resolved
```

---

### 7. Diagnostics & Connectivity Flow (`testConnection` / `checkClerk`)

Tests native SDK availability and live network connectivity to `https://api.clerk.com/v1/environment`.

```mermaid
sequenceDiagram
    autonumber
    actor App as Cordova / OutSystems App
    participant JS as echo.js
    participant Native as Native Engine (Echo.kt / EchoPlugin.swift)
    participant ClerkAPI as Clerk API (api.clerk.com)

    App->>JS: testConnection(publishableKey)
    JS->>Native: exec('Echo', 'testConnection', [publishableKey])
    
    Native->>Native: Verify Clerk SDK availability & initialize
    Native->>ClerkAPI: GET https://api.clerk.com/v1/environment (Bearer PK)
    ClerkAPI-->>Native: HTTP Response Code (e.g. 200 OK)
    
    Native->>Native: Assemble diagnostics (sdkAvailable, isSDKInitialized, networkReachable, httpResponseCode)
    Native-->>JS: callbackContext.success({ status: "success", diagnostics })
    JS-->>App: Return diagnostic payload
```

---

## 5. Auto-Healing on iOS (`dev_browser_unauthenticated`)

In development Clerk instances, session tokens are tied to a `_clerk_db_jwt` browser cookie/token. When a development session expires or a database resets, Clerk returns:

```json
{
  "errors": [
    {
      "code": "dev_browser_unauthenticated",
      "message": "Dev browser unauthenticated",
      "long_message": "The development browser session has expired."
    }
  ]
}
```

The iOS native engine handles this transparently via `purgeAllClerkCookies()`:
1. Clears `clerk_dev_browser_jwt` from Keychain.
2. Removes all cookies from `HTTPCookieStorage.shared`.
3. Clears data from `WKWebsiteDataStore.default()`.
4. Automatically retries the authentication request with a fresh state.

---

## 6. OutSystems MABS Integration & Keychain Entitlements

The plugin automatically configures the Apple Keychain Sharing Entitlements inside [`plugin.xml`](file:///d:/Luvelo/Plugins/clerk-testing-testing/plugin.xml):

```xml
<config-file target="**/Entitlements-Debug.plist" parent="keychain-access-groups">
    <array>
        <string>$(AppIdentifierPrefix)org.luvelo.dev.shared</string>
    </array>
</config-file>

<config-file target="**/Entitlements-Release.plist" parent="keychain-access-groups">
    <array>
        <string>$(AppIdentifierPrefix)org.luvelo.dev.shared</string>
    </array>
</config-file>
```

When building sibling apps in OutSystems MABS with the same Apple Developer Team Certificate, both apps share the same Keychain partition, enabling instantaneous Single Sign-On.
