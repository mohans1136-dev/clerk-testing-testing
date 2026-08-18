# Cordova Android Plugin in Kotlin (`cordova-plugin-echo`)

A simple Apache Cordova Android plugin written in **Kotlin**, based on the tutorial by Erisu (*The Web Tub*). This repository is structured for standard Cordova Mobile Applications as well as **OutSystems Mobile Applications**.

---

## 📁 Repository Structure

```
echo-just-config/
├── package.json
├── plugin.xml
├── www/
│   └── echo.js
└── src/
    └── android/
        └── org/
            └── apache/
                └── cordova/
                    └── plugin/
                        └── echo/
                            └── Echo.kt
```

---

## 🚀 Key Concepts: Kotlin in Cordova

Native Kotlin support was introduced in `cordova-android@9.0.0+`.

In `plugin.xml`, Kotlin support is declared via the following `<preference>` tags inside `<config-file target="res/xml/config.xml">`:

```xml
<preference name="GradlePluginKotlinEnabled" value="true" />
<preference name="GradlePluginKotlinCodeStyle" value="official" />
<preference name="GradlePluginKotlinVersion" value="1.9.24" />
```

This instructs the Cordova Android build system (and OutSystems MABS) to enable the Kotlin Gradle plugin during Android compilation.

---

## 💻 API Reference

### 1. `cordova.plugins.echo.echo(phrase, successCallback, errorCallback)`

Executes a synchronous echo returning the string back.

```javascript
cordova.plugins.echo.echo(
    "Hello from OutSystems!",
    function(result) {
        console.log("Success:", result); // Output: "Hello from OutSystems!"
    },
    function(error) {
        console.error("Error:", error);
    }
);
```

### 2. `cordova.plugins.echo.echoAsync(phrase, successCallback, errorCallback)`

Executes an asynchronous echo using `cordova.threadPool`, returning a JSON payload.

```javascript
cordova.plugins.echo.echoAsync(
    "Hello Async!",
    function(response) {
        console.log("Status:", response.status);     // "success"
        console.log("Message:", response.message);   // "Hello Async!"
        console.log("Language:", response.language); // "Kotlin"
        console.log("Timestamp:", response.timestamp);
    },
    function(error) {
        console.error("Error:", error);
    }
);
```

### 3. `cordova.plugins.echo.add(num1, num2, successCallback, errorCallback)`

Adds two numbers natively in Kotlin and returns a JSON payload containing `sum`, `num1`, and `num2`.

```javascript
cordova.plugins.echo.add(
    15.5,
    24.5,
    function(response) {
        console.log("Num1:", response.num1); // 15.5
        console.log("Num2:", response.num2); // 24.5
        console.log("Sum:", response.sum);   // 40
    },
    function(error) {
        console.error("Error:", error);
    }
);
```

### 4. `cordova.plugins.echo.checkClerk(publishableKey, successCallback, errorCallback)`

Checks whether the Clerk Android SDK (`com.clerk.api.Clerk`) is loaded on the Android runtime classpath and optionally initializes it if a `publishableKey` string is provided.

```javascript
cordova.plugins.echo.checkClerk(
    "pk_test_...", // optional publishable key
    function(response) {
        console.log("SDK Available:", response.sdkAvailable); // true
        console.log("Initialized:", response.initialized);   // true/false
        console.log("Message:", response.message);
    },
    function(error) {
        console.error("Clerk integration error:", error);
    }
);
```

### 5. `cordova.plugins.echo.initializeClerk(publishableKey, successCallback, errorCallback)`

Initializes the Clerk Android SDK with the specified Clerk Publishable Key.

```javascript
cordova.plugins.echo.initializeClerk(
    "pk_test_...",
    function(response) {
        console.log("Status:", response.status);           // "success"
        console.log("Message:", response.message);         // "Clerk SDK initialized successfully."
        console.log("PublishableKey:", response.publishableKey);
    },
    function(error) {
        console.error("Initialization error:", error);
    }
);
```

### 6. `cordova.plugins.echo.signInWithPassword(identifier, password, successCallback, errorCallback)`

Authenticates a user using email/username and password via Clerk SDK.

```javascript
cordova.plugins.echo.signInWithPassword(
    "user@example.com",
    "password123",
    function(response) {
        console.log("Status:", response.status);               // "success"
        console.log("Session ID:", response.createdSessionId);
        console.log("Sign In ID:", response.signInId);
    },
    function(error) {
        console.error("Sign in failed:", error.message || error);
    }
);
```

### 7. `cordova.plugins.echo.signOut(successCallback, errorCallback)`

Signs out the active user session via Clerk SDK.

```javascript
cordova.plugins.echo.signOut(
    function(response) {
        console.log("Status:", response.status);   // "success"
        console.log("Message:", response.message); // "Signed out successfully"
    },
    function(error) {
        console.error("Sign out failed:", error);
    }
);
```

### 8. `cordova.plugins.echo.getCurrentUser(successCallback, errorCallback)`

Retrieves the currently active user session status.

```javascript
cordova.plugins.echo.getCurrentUser(
    function(response) {
        console.log("Is Signed In:", response.isSignedIn);
        if (response.isSignedIn) {
            console.log("User ID:", response.userId);
            console.log("Session ID:", response.sessionId);
        }
    },
    function(error) {
        console.error("Error retrieving user status:", error);
    }
);
```

### 9. `cordova.plugins.echo.reloadFromSharedStorage(successCallback, errorCallback)`

Manually forces session reconciliation across trusted sibling apps on the same device.

```javascript
cordova.plugins.echo.reloadFromSharedStorage(
    function(response) {
        console.log("State Changed:", response.stateChanged); // true if sibling app changed session
    },
    function(error) {
        console.error("Reload error:", error);
    }
);
```

---

## ⚡ Integration with OutSystems Mobile Apps

To use this Kotlin plugin in OutSystems Reactive / Mobile Applications:

### Step 1: Package the Plugin

You can reference this plugin in OutSystems either via a Git URL or a ZIP package:

- **Git Repository**: Push this directory to your Git server (e.g. `https://github.com/your-org/cordova-plugin-echo.git`).
- **ZIP File**: Zip the contents of the `echo-just-config` directory and host it on an accessible HTTPS URL or upload it to OutSystems Resource assets.

### Step 2: Add Extensibility Configurations in OutSystems Service Studio

In your OutSystems Mobile Module:
1. Open the Module Properties in Service Studio.
2. Edit **Extensibility Configurations**.
3. Add the JSON configuration referencing your plugin:

#### Using Git URL:
```json
{
    "plugin": {
        "url": "https://github.com/your-org/cordova-plugin-echo.git"
    }
}
```

#### Using ZIP URL:
```json
{
    "plugin": {
        "url": "https://your-domain.com/plugins/cordova-plugin-echo.zip"
    }
}
```

### Step 3: Call the Plugin in OutSystems JavaScript Node

Inside a Client Action in Service Studio, add a **JavaScript Element**:

```javascript
// Calling Echo
if (window.cordova && window.cordova.plugins && window.cordova.plugins.echo) {
    window.cordova.plugins.echo.echo(
        $parameters.InputMessage,
        function(result) {
            $parameters.OutputMessage = result;
            $parameters.Success = true;
            $resolve();
        },
        function(error) {
            $parameters.ErrorMessage = error;
            $parameters.Success = false;
            $resolve();
        }
    );
} else {
    $parameters.ErrorMessage = "Plugin not available on this platform/device.";
    $parameters.Success = false;
    $resolve();
}
```

#### Calling Addition in OutSystems JavaScript Node:

```javascript
if (window.cordova && window.cordova.plugins && window.cordova.plugins.echo) {
    window.cordova.plugins.echo.add(
        $parameters.Number1,
        $parameters.Number2,
        function(response) {
            $parameters.ResultSum = response.sum;
            $parameters.Success = true;
            $resolve();
        },
        function(error) {
            $parameters.ErrorMessage = error;
            $parameters.Success = false;
            $resolve();
        }
    );
} else {
    $parameters.ErrorMessage = "Plugin not available on this platform/device.";
    $parameters.Success = false;
    $resolve();
}
```

#### Checking Clerk Android Integration in OutSystems JavaScript Node:

```javascript
if (window.cordova && window.cordova.plugins && window.cordova.plugins.echo) {
    window.cordova.plugins.echo.checkClerk(
        $parameters.PublishableKey, // e.g. "pk_test_..." or empty string ""
        function(response) {
            $parameters.IsAvailable = response.sdkAvailable;
            $parameters.IsInitialized = response.initialized;
            $parameters.Message = response.message;
            $parameters.Success = true;
            $resolve();
        },
        function(error) {
            $parameters.ErrorMessage = typeof error === 'object' ? JSON.stringify(error) : error;
            $parameters.Success = false;
            $resolve();
        }
    );
} else {
    $parameters.ErrorMessage = "Plugin not available on this platform/device.";
    $parameters.Success = false;
    $resolve();
}
```

---

## 🛠️ Testing in Standard Cordova CLI

1. Create a Cordova app:
   ```bash
   cordova create testApp com.example.testapp TestApp
   cd testApp
   cordova platform add android@12.0.0
   ```

2. Add this plugin from local path:
   ```bash
   cordova plugin add ../echo-just-config
   ```

3. Build and run:
   ```bash
   cordova run android
   ```

