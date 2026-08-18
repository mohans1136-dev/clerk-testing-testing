var exec = require('cordova/exec');

/**
 * Echo Plugin JavaScript Interface
 */
var Echo = {
    /**
     * Synchronous / Direct Echo
     * @param {string} phrase - String message to be echoed back
     * @param {function} successCallback - Callback on success
     * @param {function} errorCallback - Callback on error
     */
    echo: function (phrase, successCallback, errorCallback) {
        if (typeof phrase !== 'string' || phrase.trim() === '') {
            if (typeof errorCallback === 'function') {
                errorCallback('Expected a non-empty string argument.');
            }
            return;
        }
        exec(successCallback, errorCallback, 'Echo', 'echo', [phrase]);
    },

    /**
     * Async Thread Pool Echo returning a JSON payload
     * @param {string} phrase - String message to be echoed back
     * @param {function} successCallback - Callback returning JSON object
     * @param {function} errorCallback - Callback on error
     */
    echoAsync: function (phrase, successCallback, errorCallback) {
        if (typeof phrase !== 'string' || phrase.trim() === '') {
            if (typeof errorCallback === 'function') {
                errorCallback('Expected a non-empty string argument.');
            }
            return;
        }
        exec(successCallback, errorCallback, 'Echo', 'echoAsync', [phrase]);
    },

    /**
     * Add two numbers in native Kotlin
     * @param {number} num1 - First number
     * @param {number} num2 - Second number
     * @param {function} successCallback - Callback returning JSON object with sum
     * @param {function} errorCallback - Callback on error
     */
    add: function (num1, num2, successCallback, errorCallback) {
        var n1 = parseFloat(num1);
        var n2 = parseFloat(num2);
        if (isNaN(n1) || isNaN(n2)) {
            if (typeof errorCallback === 'function') {
                errorCallback('Expected two valid numeric arguments.');
            }
            return;
        }
        exec(successCallback, errorCallback, 'Echo', 'add', [n1, n2]);
    },

    /**
     * Check Clerk SDK integration status on Android
     * @param {string} [publishableKey] - Optional Clerk Publishable Key (e.g. "pk_test_...")
     * @param {function} successCallback - Callback returning JSON object with Clerk status
     * @param {function} errorCallback - Callback on error
     */
    checkClerk: function (publishableKey, successCallback, errorCallback) {
        if (typeof publishableKey === 'function') {
            errorCallback = successCallback;
            successCallback = publishableKey;
            publishableKey = '';
        }
        var key = (typeof publishableKey === 'string') ? publishableKey : '';
        exec(successCallback, errorCallback, 'Echo', 'checkClerk', [key]);
    },

    /**
     * Initialize Clerk Android SDK with a publishable key and optional Shared Session Sync flag
     * @param {string} publishableKey - Clerk Publishable Key
     * @param {boolean} [enableSharedSessionSync=true] - Whether to enable shared session sync across trusted sibling apps
     * @param {function} successCallback - Callback returning JSON object on success
     * @param {function} errorCallback - Callback on error
     */
    initializeClerk: function (publishableKey, enableSharedSessionSync, successCallback, errorCallback) {
        if (typeof enableSharedSessionSync === 'function') {
            errorCallback = successCallback;
            successCallback = enableSharedSessionSync;
            enableSharedSessionSync = true;
        }
        if (typeof publishableKey !== 'string' || publishableKey.trim() === '') {
            if (typeof errorCallback === 'function') {
                errorCallback('Expected a non-empty publishableKey string argument.');
            }
            return;
        }
        var syncEnabled = (typeof enableSharedSessionSync === 'boolean') ? enableSharedSessionSync : true;
        exec(successCallback, errorCallback, 'Echo', 'initializeClerk', [publishableKey, syncEnabled]);
    },

    /**
     * Sign in a user with identifier (email/username) and password via Clerk SDK
     * @param {string} identifier - User email, phone, or username
     * @param {string} password - User password
     * @param {function} successCallback - Callback returning JSON object on success
     * @param {function} errorCallback - Callback returning JSON object on error
     */
    signInWithPassword: function (identifier, password, successCallback, errorCallback) {
        if (typeof identifier !== 'string' || identifier.trim() === '') {
            if (typeof errorCallback === 'function') {
                errorCallback('Expected a non-empty identifier string argument.');
            }
            return;
        }
        if (typeof password !== 'string' || password.trim() === '') {
            if (typeof errorCallback === 'function') {
                errorCallback('Expected a non-empty password string argument.');
            }
            return;
        }
        exec(successCallback, errorCallback, 'Echo', 'signInWithPassword', [identifier, password]);
    },

    /**
     * Sign out the active user and clear session via Clerk SDK
     * @param {function} successCallback - Callback returning JSON object on success
     * @param {function} errorCallback - Callback returning JSON object on error
     */
    signOut: function (successCallback, errorCallback) {
        exec(successCallback, errorCallback, 'Echo', 'signOut', []);
    },

    /**
     * Get details for the currently active Clerk user session
     * @param {function} successCallback - Callback returning user metadata or status
     * @param {function} errorCallback - Callback returning error object
     */
    getCurrentUser: function (successCallback, errorCallback) {
        exec(successCallback, errorCallback, 'Echo', 'getCurrentUser', []);
    },

    /**
     * Reconcile and reload shared session state across sibling apps manually
     * @param {function} successCallback - Callback returning JSON object with stateChanged boolean
     * @param {function} errorCallback - Callback returning error object
     */
    reloadFromSharedStorage: function (successCallback, errorCallback) {
        exec(successCallback, errorCallback, 'Echo', 'reloadFromSharedStorage', []);
    },

    /**
     * Run a connection diagnostic pipeline to test SDK initialization and Clerk backend connectivity
     * @param {string} [publishableKey] - Optional Clerk Publishable Key
     * @param {function} successCallback - Callback returning JSON diagnostic object
     * @param {function} errorCallback - Callback returning JSON error object
     */
    testConnection: function (publishableKey, successCallback, errorCallback) {
        if (typeof publishableKey === 'function') {
            errorCallback = successCallback;
            successCallback = publishableKey;
            publishableKey = '';
        }
        var key = (typeof publishableKey === 'string') ? publishableKey : '';
        exec(successCallback, errorCallback, 'Echo', 'testConnection', [key]);
    }
};

module.exports = Echo;
