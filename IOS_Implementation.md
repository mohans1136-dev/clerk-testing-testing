# iOS Clerk Plugin Implementation & Architecture Guide

A comprehensive architectural document and sequence specification for the **iOS Native Clerk Authentication Engine** in `cordova-plugin-echo` ([EchoPlugin.swift](src/ios/EchoPlugin.swift)).

---

## 📑 Table of Contents
1. [Architecture Overview](#-architecture-overview)
2. [Sequence Diagrams](#-sequence-diagrams)
   - [1. User Authentication (`signInWithPassword`)](#1-user-authentication-signinwithpassword)
   - [2. Plugin Initialization (`initializeClerk`)](#2-plugin-initialization-initializeclerk)
   - [3. Current User & Live Profile Refresh (`getCurrentUser`)](#3-current-user--live-profile-refresh-getcurrentuser)
   - [4. Cross-App Shared Session Sync (`reloadFromSharedStorage`)](#4-cross-app-shared-session-sync-reloadfromsharedstorage)
   - [5. Sign Out & Comprehensive Cache Purge (`signOut`)](#5-sign-out--comprehensive-cache-purge-signout)
   - [6. Connection Diagnostic Pipeline (`testConnection`)](#6-connection-diagnostic-pipeline-testconnection)
3. [iOS Shared Keychain Storage Specification](#-ios-shared-keychain-storage-specification)
4. [Publishable Key Decoding & Frontend API Host Discovery](#-publishable-key-decoding--frontend-api-host-discovery)
5. [Dev Browser Cookie Auto-Healing Mechanism](#-dev-browser-cookie-auto-healing-mechanism)
6. [OutSystems MABS Build & Entitlements Configuration](#-outsystems-mabs-build--entitlements-configuration)

---

## 🏛 Architecture Overview

The iOS implementation operates as a high-performance native Swift engine communicating directly with the **Clerk Frontend REST API** and Apple's **Security (Keychain) Framework**.

```mermaid
graph TB
    subgraph "Cordova / OutSystems WebView"
        JS["echo.js (window.echo / cordova.plugins.echo)"]
    end

    subgraph "Native iOS Plugin Bridge"
        CDV["Cordova Plugin Bridge (CDVCommandDelegate)"]
        Echo["EchoPlugin.swift (CDVPlugin)"]
    end

    subgraph "Local Secure Storage & Caching"
        Keychain[("iOS Shared Keychain\nService: com.luvelo.clerk.sharedservice\nAccess Group: $(AppIdentifierPrefix)org.luvelo.dev.shared")]
        Cookies[("HTTPCookieStorage & WKWebsiteDataStore")]
    end

    subgraph "Clerk Cloud Infrastructure"
        ClerkAPI["Clerk Frontend API\nhttps://<decoded-clerk-host>/v1"]
    end

    JS -->|cordova.exec| CDV
    CDV --> Echo
    Echo <--> Keychain
    Echo <--> Cookies
    Echo <-->|URLSession HTTPS REST| ClerkAPI
```

---

## 📊 Sequence Diagrams

### 1. Hosted Authentication (`startHostedAuth` - Microsoft Enterprise SSO & Account Portal)

Uses Apple's native **`ASWebAuthenticationSession`** to present Clerk's hosted Account Portal in a secure sheet overlay. Automatically supports **Microsoft Enterprise SSO (OIDC)**, Passkeys, Google/Apple login, and MFA, persisting authenticated session tokens into the Shared Keychain.

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant App as OutSystems Mobile App (iOS)
    participant JS as echo.js Bridge
    participant Swift as EchoPlugin.swift (iOS)
    participant ASWeb as ASWebAuthenticationSession
    participant ClerkPortal as Clerk Account Portal
    participant Microsoft as Microsoft Entra ID (OIDC)
    participant Keychain as iOS Shared Keychain (org.luvelo.dev.shared)

    App->>JS: window.echo.startHostedAuth({ mode: 'sign_in' })
    JS->>Swift: exec("Echo", "startHostedAuth", [mode])
    
    Swift->>Swift: Resolve Account Portal URL & Callback Scheme
    Swift->>ASWeb: Initialize ASWebAuthenticationSession
    ASWeb->>User: Display system authentication prompt
    ASWeb->>ClerkPortal: Load Account Portal in secure browser sheet
    
    opt Microsoft Enterprise SSO
        User->>ClerkPortal: Click "Sign in with Microsoft"
        ClerkPortal->>Microsoft: Azure AD OAuth Flow & Conditional Access
        Microsoft-->>ClerkPortal: OAuth Callback
    end

    ClerkPortal-->>ASWeb: Redirect with Session tokens
    ASWeb-->>Swift: Completion Handler with Callback URL
    
    Swift->>Swift: Extract created_session_id & dev_browser_jwt
    Swift->>Swift: Live query https://{host}/v1/client for User Profile
    Swift->>Keychain: Persist (sessionId, userId, names, email, tokens)
    Swift-->>JS: CDVPluginResult(OK, { status: "success", sessionId, userId, email, firstName, lastName })
    JS-->>App: Return authenticated user data
```

---

### 2. User Authentication (`signInWithPassword`)

Handles authentication using the Clerk Frontend API, dev-browser session coordination, automatic recovery from stale development tokens (`dev_browser_unauthenticated`), and secure session persistence to the shared iOS Keychain.

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant JS as JavaScript Bridge (echo.js)
    participant Bridge as Cordova CDVCommandDelegate
    participant Plugin as EchoPlugin.swift
    participant Keychain as iOS Shared Keychain
    participant WKStore as WebKit & Cookie Storage
    participant Clerk as Clerk Frontend API

    User->>JS: window.echo.signInWithPassword(email, pass, cbSuccess, cbError)
    JS->>Bridge: cordova.exec("Echo", "signInWithPassword", [identifier, password])
    Bridge->>Plugin: signInWithPassword(command)
    
    Plugin->>Keychain: loadFromKeychain("clerk_publishable_key")
    Keychain-->>Plugin: Publishable Key (pk_test_...)
    
    Plugin->>Plugin: getFrontendApiHost(pk) -> decodes Host from Base64
    Plugin->>Keychain: loadFromKeychain("clerk_dev_browser_jwt")
    Keychain-->>Plugin: dbJwt (if available)

    Note over Plugin,Clerk: Primary Sign-In Request
    Plugin->>Clerk: POST https://{host}/v1/client/sign_ins?_clerk_js_version=5.0.0<br/>Headers: Authorization: Bearer {pk}, Clerk-Db-Jwt: {dbJwt}<br/>Body: strategy=password&identifier=...&password=...
    Clerk-->>Plugin: HTTP Response (Status Code & JSON Body)

    Plugin->>Plugin: extractAndSaveDevBrowserJwt(response)
    opt Header 'Clerk-Db-Jwt' or Cookie '__clerk_db_jwt' Present
        Plugin->>Keychain: saveToKeychain("clerk_dev_browser_jwt", dbJwt)
    end

    alt Error Code: dev_browser_unauthenticated (Stale Token Detected)
        Note over Plugin,WKStore: Dev Browser Auto-Healing Flow
        Plugin->>Keychain: deleteFromKeychain("clerk_dev_browser_jwt")
        Plugin->>WKStore: purgeAllClerkCookies() (HTTPCookieStorage + WKWebsiteDataStore)
        Plugin->>Clerk: POST /v1/client/sign_ins (Retry with isRetry=true)
        Clerk-->>Plugin: HTTP 200 OK + Client Payload
    end

    alt Authentication Success
        Plugin->>Plugin: Extract created_session_id, JWT token, User ID, Profile details
        Plugin->>Keychain: saveToKeychain("active_clerk_session_id", sessionId)
        Plugin->>Keychain: saveToKeychain("active_clerk_session_jwt", jwtToken)
        Plugin->>Keychain: saveToKeychain("active_clerk_user_id", userId)
        Plugin->>Keychain: saveToKeychain("active_clerk_first_name", firstName)
        Plugin->>Keychain: saveToKeychain("active_clerk_last_name", lastName)
        Plugin->>Keychain: saveToKeychain("active_clerk_email", email)
        
        Plugin->>Bridge: CDVPluginResult(OK, {status: "success", signInStatus: "COMPLETE", userId, sessionId, ...})
        Bridge->>JS: cbSuccess(response)
        JS-->>User: Authentication Complete
    else Authentication Failure (Invalid Credentials / API Error)
        Plugin->>Bridge: CDVPluginResult(ERROR, {status: "error", errorCode, message})
        Bridge->>JS: cbError(error)
        JS-->>User: Display Error Message
    end
```

---

### 2. Plugin Initialization (`initializeClerk`)

Configures the native engine, caches the publishable key in memory, and persists it into the shared Keychain for cross-app sibling discovery.

```mermaid
sequenceDiagram
    autonumber
    participant JS as JavaScript (echo.js)
    participant Plugin as EchoPlugin.swift
    participant Keychain as iOS Shared Keychain

    JS->>Plugin: initializeClerk(publishableKey, enableSharedSessionSync)
    Note over Plugin: Validate publishableKey argument
    Plugin->>Plugin: inMemoryPublishableKey = key
    Plugin->>Keychain: saveToKeychain("clerk_publishable_key", key)
    Keychain-->>Plugin: Stored with kSecAttrAccessibleAfterFirstUnlock
    Plugin->>JS: CDVPluginResult(OK, {status: "success", publishableKey, sharedSessionSyncEnabled: true})
```

---

### 3. Current User & Live Profile Refresh (`getCurrentUser`)

Performs a local Keychain lookup followed by a live, non-blocking background query to Clerk's `/v1/client` endpoint to synchronize profile changes.

```mermaid
sequenceDiagram
    autonumber
    participant JS as JavaScript (echo.js)
    participant Plugin as EchoPlugin.swift
    participant Keychain as iOS Shared Keychain
    participant Clerk as Clerk Frontend API

    JS->>Plugin: getCurrentUser()
    Plugin->>Keychain: Read active_clerk_session_id, active_clerk_user_id, profile keys
    
    alt No active session or user in Keychain
        Plugin->>JS: CDVPluginResult(OK, {status: "success", isSignedIn: false})
    else Active session found
        Note over Plugin,Clerk: Best-effort live refresh (3.0s timeout)
        Plugin->>Clerk: GET https://{host}/v1/client (Bearer {pk}, Clerk-Db-Jwt: {dbJwt})
        
        alt Clerk Response OK (200 / 304)
            Clerk-->>Plugin: Updated Client & User Profile JSON
            Plugin->>Keychain: Update fresh user_id, first_name, last_name
            Plugin->>Plugin: Update response payload with fresh attributes
        else Network Timeout / Offline
            Note over Plugin: Fall back seamlessly to cached Keychain attributes
        end
        
        Plugin->>JS: CDVPluginResult(OK, {status: "success", isSignedIn: true, userId, firstName, lastName, email, sessionId})
    end
```

---

### 4. Cross-App Shared Session Sync (`reloadFromSharedStorage`)

Allows sibling OutSystems applications sharing the same App Group entitlement (`org.luvelo.dev.shared`) to inherit login state without prompting the user to sign in again.

```mermaid
sequenceDiagram
    autonumber
    participant App2 as Sibling OutSystems App
    participant Plugin as EchoPlugin.swift (App 2)
    participant Keychain as Shared Keychain (org.luvelo.dev.shared)

    App2->>Plugin: reloadFromSharedStorage()
    Plugin->>Keychain: loadFromKeychain("active_clerk_session_jwt")
    Plugin->>Keychain: loadFromKeychain("active_clerk_session_id")
    
    alt Session Token / ID exists in Shared Keychain
        Keychain-->>Plugin: Active Session Credentials
        Plugin->>App2: CDVPluginResult(OK, {status: "success", stateChanged: true, sessionId: "sess_..."})
    else No session in Shared Keychain
        Keychain-->>Plugin: nil
        Plugin->>App2: CDVPluginResult(OK, {status: "success", stateChanged: false, sessionId: ""})
    end
```

---

### 5. Sign Out & Comprehensive Cache Purge (`signOut`)

Revokes the session on Clerk's servers, purges all Keychain keys, and cleans all WebKit cookies and website data.

```mermaid
sequenceDiagram
    autonumber
    participant JS as JavaScript (echo.js)
    participant Plugin as EchoPlugin.swift
    participant Clerk as Clerk Frontend API
    participant Keychain as iOS Shared Keychain
    participant WKStore as Cookie & WebKit Store

    JS->>Plugin: signOut()
    Plugin->>Keychain: Read active_clerk_session_id & active_clerk_session_jwt
    
    opt Session ID is present
        Plugin->>Clerk: POST https://{host}/v1/client/sessions/{sessionId}/remove (Bearer {jwt})
        Clerk-->>Plugin: Session Revocation Acknowledged
    end

    Note over Plugin,Keychain: Purge Keychain Keys
    Plugin->>Keychain: deleteFromKeychain("active_clerk_session_jwt")
    Plugin->>Keychain: deleteFromKeychain("active_clerk_session_id")
    Plugin->>Keychain: deleteFromKeychain("active_clerk_user_id")
    Plugin->>Keychain: deleteFromKeychain("active_clerk_first_name")
    Plugin->>Keychain: deleteFromKeychain("active_clerk_last_name")
    Plugin->>Keychain: deleteFromKeychain("active_clerk_email")
    Plugin->>Keychain: deleteFromKeychain("clerk_dev_browser_jwt")

    Note over Plugin,WKStore: Purge Web & Cookie Storage
    Plugin->>WKStore: HTTPCookieStorage.shared.deleteCookie(...)
    Plugin->>WKStore: WKWebsiteDataStore.default().removeData(allWebsiteDataTypes)

    Plugin->>JS: CDVPluginResult(OK, {status: "success", message: "Signed out successfully"})
```

---

### 6. Connection Diagnostic Pipeline (`testConnection`)

Executes an isolated network probe to test connectivity with Clerk's central API (`api.clerk.com`).

```mermaid
sequenceDiagram
    autonumber
    participant JS as JavaScript (echo.js)
    participant Plugin as EchoPlugin.swift
    participant ClerkCenter as https://api.clerk.com/v1/environment

    JS->>Plugin: testConnection(publishableKey)
    Plugin->>ClerkCenter: GET /v1/environment (Timeout: 5.0s, Authorization: Bearer {pk})
    ClerkCenter-->>Plugin: HTTP Response
    Plugin->>JS: CDVPluginResult(OK, {status: "success", diagnostics: {networkReachable: true, httpResponseCode: 200}})
```

---

## 🔑 iOS Shared Keychain Storage Specification

All credentials and profile attributes are stored using Apple's Security Framework with `kSecAttrAccessibleAfterFirstUnlock`.

* **Keychain Service:** `com.luvelo.clerk.sharedservice`
* **Entitlement Access Group:** `$(AppIdentifierPrefix)org.luvelo.dev.shared`

| Keychain Account Key | Data Type | Description |
| :--- | :--- | :--- |
| `clerk_publishable_key` | `String` | Clerk Publishable Key (`pk_test_...` or `pk_live_...`) |
| `active_clerk_session_jwt` | `String` | Active Clerk Client Session JWT used for Authorization headers |
| `active_clerk_session_id` | `String` | Active Clerk Session Identifier (`sess_...`) |
| `clerk_dev_browser_jwt` | `String` | Dev Browser Session Token (`__clerk_db_jwt`) for development environments |
| `active_clerk_user_id` | `String` | Clerk User Identifier (`user_...`) |
| `active_clerk_first_name` | `String` | User First Name |
| `active_clerk_last_name` | `String` | User Last Name |
| `active_clerk_email` | `String` | User Primary Email Address |

---

## 🔍 Publishable Key Decoding & Frontend API Host Discovery

Clerk Publishable Keys encode the target Frontend API Host in their third component:
`pk_test_<Base64EncodedHost>$`

The plugin decodes the host dynamically at runtime via `getFrontendApiHost(publishableKey:)`:
1. Strips prefix `pk_test_` or `pk_live_`.
2. Normalizes URL-safe Base64 padding (`-` to `+`, `_` to `/`, remainder modulo 4 padding `=`).
3. Decodes the UTF-8 string representation (e.g. `clerk.yourdomain.com` or `viable-badger-12.clerk.accounts.dev`).
4. Constructs HTTPS URLs for direct REST communication.

---

## 🛡️ Dev Browser Cookie Auto-Healing Mechanism

In Clerk development instances (`pk_test_...`), sessions require dev-browser synchronization via `_clerk_db_jwt`. If the dev-browser token expires or becomes invalid, Clerk returns:

```json
{
  "errors": [{
    "code": "dev_browser_unauthenticated",
    "message": "Dev browser unauthenticated"
  }]
}
```

**The iOS Plugin Auto-Healing Workflow:**
1. Intercepts `dev_browser_unauthenticated` error code.
2. Invokes `purgeAllClerkCookies()`, clearing:
   - `clerk_dev_browser_jwt` from iOS Keychain.
   - All cookies from `HTTPCookieStorage.shared`.
   - All website cache/cookies from `WKWebsiteDataStore.default()`.
3. Retries the sign-in request cleanly with `isRetry: true`.
4. Successfully completes sign-in without user friction.

---

## 🛠️ OutSystems MABS Build & Entitlements Configuration

The plugin automatically injects the necessary Keychain Sharing entitlements into all build variants via [plugin.xml](plugin.xml):

```xml
<!-- Keychain Sharing Entitlements for OutSystems MABS Cloud Builds -->
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

<config-file target="**/*.entitlements" parent="keychain-access-groups">
    <array>
        <string>$(AppIdentifierPrefix)org.luvelo.dev.shared</string>
    </array>
</config-file>
```
