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
     * Initialize Clerk Android SDK with a publishable key
     * @param {string} publishableKey - Clerk Publishable Key
     * @param {function} successCallback - Callback returning JSON object on success
     * @param {function} errorCallback - Callback on error
     */
    initializeClerk: function (publishableKey, successCallback, errorCallback) {
        if (typeof publishableKey !== 'string' || publishableKey.trim() === '') {
            if (typeof errorCallback === 'function') {
                errorCallback('Expected a non-empty publishableKey string argument.');
            }
            return;
        }
        exec(successCallback, errorCallback, 'Echo', 'initializeClerk', [publishableKey]);
    }
};

module.exports = Echo;
