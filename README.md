# Cordova Clerk Authentication & Shared Session Plugin (`cordova-plugin-echo`)

A production-ready **Cross-Platform Apache Cordova Plugin** providing native **Clerk Authentication** and **Cross-App Session Sharing (Single Sign-On)** for **Android (Kotlin)** and **iOS (Swift)**, built specifically for **OutSystems Mobile Applications (MABS)** and standard Cordova projects.

---

## 🌟 Key Highlights & Capabilities

- 🔐 **Native Clerk Authentication:** Full support for `initializeClerk`, `signInWithPassword`, `signOut`, and `getCurrentUser`.
- 🔄 **Cross-App Session Sharing (SSO):**
  - **Android:** Powered by Clerk Android SDK's `SharedSessionSyncConfig`.
  - **iOS:** Powered by Apple **Keychain Sharing Access Groups** (`$(AppIdentifierPrefix)org.luvelo.dev.shared`) configured automatically for OutSystems MABS cloud builds.
- 🛡️ **Dev Browser Cookie Auto-Healing:** Solves the iOS development instance `dev_browser_unauthenticated` error via automated cookie/token purging and transparent retries.
- 📱 **OutSystems MABS 10+ Ready:** Supports Kotlin 2.0.21 on Android and Swift 5.0+ on iOS with zero Xcode or manual build steps required.

---

## 📁 Repository Structure

```
clerk-testing-testing/
├── package.json
├── plugin.xml                                # Cordova plugin manifest & iOS Keychain Entitlements
├── README.md                                 # Full documentation & OutSystems integration guide
├── Android_Implementation.md                 # Full Android architecture & sequence diagrams
├── www/
│   └── echo.js                               # JavaScript Bridge (window.echo & cordova.plugins.echo)
└── src/
    ├── android/
    │   ├── build-extras.gradle               # Kotlin & Gradle dependencies
    │   └── org/apache/cordova/plugin/echo/
    │       └── Echo.kt                       # Android Kotlin native engine (com.clerk:clerk-android-api)
    └── ios/
        ├── EchoPlugin-Bridging-Header.h      # Cordova Objective-C bridging header
        └── EchoPlugin.swift                  # iOS Swift native engine (REST & Shared Keychain)
```

---

## ⚙️ OutSystems MABS Integration Guide

### Step 1: Add Extensibility Configurations in OutSystems Service Studio

In your OutSystems Mobile / Reactive Application module:
1. Open the **Module Properties** in Service Studio.
2. Open **Extensibility Configurations**.
3. Paste the following JSON configuration referencing this repository:

```json
{
    "plugin": {
        "url": "https://github.com/mohans1136-dev/clerk-testing-testing.git"
    }
}
```

> [!TIP]
> To lock the build to a specific commit hash, append the commit sha to the URL:  
> `"url": "https://github.com/mohans1136-dev/clerk-testing-testing#ea9f3fd"`

---

### Step 2: iOS Keychain Sharing for Sibling Apps

Both sibling apps (e.g. `ClerkApp1` and `ClerkApp2`) must:
1. Install this plugin (which applies the `$(AppIdentifierPrefix)org.luvelo.dev.shared` entitlement via `plugin.xml`).
2. Be signed with the **same Apple Developer Team ID** during the MABS build.

---

## 💻 Complete JavaScript API Reference

All methods are available on both `cordova.plugins.echo` and `window.echo`.

---

### 1. `initializeClerk(publishableKey, enableSharedSessionSync, success, error)`

Initializes the Clerk engine with your Publishable Key (`pk_test_...` or `pk_live_...`).

```javascript
cordova.plugins.echo.initializeClerk(
    "pk_test_YOUR_CLERK_PUBLISHABLE_KEY",
    true, // enableSharedSessionSync (Boolean)
    function(response) {
        console.log("Initialized successfully:", response.message);
        console.log("Publishable Key:", response.publishableKey);
    },
    function(error) {
        console.error("Initialization failed:", error);
    }
);
```

---

### 2. `signInWithPassword(identifier, password, success, error)`

Authenticates a user with email/username and password. Automatically stores the active session in shared storage/Keychain.

```javascript
cordova.plugins.echo.signInWithPassword(
    "user@example.com",
    "securePassword123",
    function(response) {
        console.log("Sign In Status:", response.signInStatus); // "COMPLETE"
        console.log("Created Session ID:", response.createdSessionId);
        console.log("User ID:", response.userId);
        console.log("First Name:", response.firstName);
    },
    function(error) {
        console.error("Sign in failed:", error.message || error);
    }
);
```

---

### 3. `getCurrentUser(success, error)`

Retrieves the currently authenticated user's session metadata and status.

```javascript
cordova.plugins.echo.getCurrentUser(
    function(response) {
        if (response.isSignedIn) {
            console.log("User is Signed In!");
            console.log("User ID:", response.userId);
            console.log("First Name:", response.firstName);
            console.log("Last Name:", response.lastName);
            console.log("Session ID:", response.sessionId);
        } else {
            console.log("User is Signed Out.");
        }
    },
    function(error) {
        console.error("Failed to query user session:", error);
    }
);
```

---

### 4. `signOut(success, error)`

Terminates the active session, revokes the token on the Clerk server, and purges all local cookies/tokens.

```javascript
cordova.plugins.echo.signOut(
    function(response) {
        console.log("Sign Out Success:", response.message);
    },
    function(error) {
        console.error("Sign Out failed:", error);
    }
);
```

---

### 5. `reloadFromSharedStorage(success, error)`

Reconciles and syncs session state from sibling apps that share the same keychain/storage group.

```javascript
cordova.plugins.echo.reloadFromSharedStorage(
    function(response) {
        if (response.stateChanged) {
            console.log("Active sibling session detected! Session ID:", response.sessionId);
        } else {
            console.log("No shared session state change.");
        }
    },
    function(error) {
        console.error("Failed to reload shared storage:", error);
    }
);
```

---

### 6. `getKeychainAccessGroup(success, error)`

Returns the configured Keychain / Storage group identifier (`org.luvelo.dev.shared`).

```javascript
cordova.plugins.echo.getKeychainAccessGroup(
    function(response) {
        console.log("Access Group:", response.accessGroup);
        console.log("Platform:", response.platform);
    },
    function(error) {
        console.error("Failed to query access group:", error);
    }
);
```

---

### 7. `checkClerk(publishableKey, success, error)`

Checks if the Clerk engine is available on the native runtime.

```javascript
cordova.plugins.echo.checkClerk(
    "pk_test_...", // optional
    function(response) {
        console.log("SDK Available:", response.sdkAvailable);
        console.log("Initialized:", response.initialized);
    },
    function(error) {
        console.error("Check Clerk error:", error);
    }
);
```

---

### 8. `testConnection(publishableKey, success, error)`

Runs a network diagnostic test to verify backend connectivity to `api.clerk.com`.

```javascript
cordova.plugins.echo.testConnection(
    "pk_test_...", // optional
    function(response) {
        console.log("Diagnostic Status:", response.status);
        console.log("Network Reachable:", response.diagnostics.networkReachable);
        console.log("HTTP Code:", response.diagnostics.httpResponseCode);
    },
    function(error) {
        console.error("Test connection failed:", error);
    }
);
```

---

### 9. Utility Methods: `echo`, `echoAsync`, `add`

```javascript
// Synchronous Echo
cordova.plugins.echo.echo("Hello OutSystems", res => console.log(res), err => console.error(err));

// Asynchronous Thread-Pool Echo
cordova.plugins.echo.echoAsync("Hello Async", res => console.log(res.message), err => console.error(err));

// Native Numeric Addition
cordova.plugins.echo.add(10, 25, res => console.log("Sum:", res.sum), err => console.error(err));
```

---

## 📱 OutSystems Client Action Example Node

Here is the standard pattern to paste into an OutSystems **JavaScript Element** inside a Client Action:

```javascript
if (window.cordova && window.cordova.plugins && window.cordova.plugins.echo) {
    window.cordova.plugins.echo.getCurrentUser(
        function(response) {
            if (response.isSignedIn) {
                $parameters.IsSignedIn = true;
                $parameters.UserId = response.userId;
                $parameters.FirstName = response.firstName;
                $parameters.SessionId = response.sessionId;
            } else {
                $parameters.IsSignedIn = false;
                $parameters.UserId = "";
            }
            $parameters.Success = true;
            $resolve();
        },
        function(error) {
            $parameters.Success = false;
            $parameters.ErrorMessage = typeof error === 'object' ? JSON.stringify(error) : error;
            $resolve();
        }
    );
} else {
    $parameters.Success = false;
    $parameters.ErrorMessage = "Clerk Echo plugin is not available on this device.";
    $resolve();
}
```

---

## 📄 License

Apache License 2.0. See [LICENSE](LICENSE) for details.
