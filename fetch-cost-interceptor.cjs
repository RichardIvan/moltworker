/**
 * Fetch interceptor for AI Gateway BYOK (Bring Your Own Key) mode
 * Build: 2026-02-05T10:14
 * 
 * This interceptor does TWO things:
 * 1. URL Rewriting: Redirects native Google API requests to Cloudflare AI Gateway
 *    (because OpenClaw doesn't pass baseUrl to the @ai-sdk/google SDK)
 * 2. BYOK Header Management: Removes API keys and adds cf-aig-authorization
 * 
 * BYOK Flow:
 * 1. SDK sends request to generativelanguage.googleapis.com with x-goog-api-key
 * 2. This interceptor REWRITES URL to AI Gateway /google-ai-studio endpoint
 * 3. This interceptor REMOVES the x-goog-api-key header  
 * 4. This interceptor ADDS cf-aig-authorization header (Gateway auth)
 * 5. Gateway receives request with NO API key → injects Provider Key from BYOK config
 * 6. Google AI Studio receives the real API key
 * 
 * Usage: NODE_OPTIONS="--require /path/to/fetch-cost-interceptor.cjs" node app.js
 * 
 * Environment variables:
 * - CF_AIG_AUTHORIZATION: API token for AI Gateway authentication (required for BYOK)
 * - AI_GATEWAY_BASE_URL: Base URL for AI Gateway (e.g., https://gateway.ai.cloudflare.com/v1/{account}/{gateway}/google-ai-studio)
 */

// BYOK authorization token (set via environment variable)
const CF_AIG_AUTHORIZATION = process.env.CF_AIG_AUTHORIZATION;
const AI_GATEWAY_BASE_URL = process.env.AI_GATEWAY_BASE_URL;

const originalFetch = globalThis.fetch;

globalThis.fetch = async function patchedFetch(input, init) {
    let url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;

    // === URL REWRITING ===
    // Intercept requests to native Google API and redirect to AI Gateway
    // This is needed because OpenClaw doesn't pass baseUrl to the @ai-sdk/google SDK
    const isNativeGoogleRequest = url && url.includes('generativelanguage.googleapis.com');

    // Embedding requests bypass AI Gateway - it returns 404 for embedContent/batchEmbedContents
    // These go directly to Google using the real GEMINI_API_KEY (set as separate secret)
    const isEmbeddingRequest = url && (url.includes(':embedContent') || url.includes(':batchEmbedContents'));

    if (isEmbeddingRequest && isNativeGoogleRequest) {
        console.log('[fetch-interceptor] Embedding request - bypassing gateway, using direct Google API');
        // Don't redirect, don't strip headers - let it go directly to Google
        return originalFetch(input, init);
    }

    if (isNativeGoogleRequest && AI_GATEWAY_BASE_URL && AI_GATEWAY_BASE_URL.includes('/google-ai-studio')) {
        // Extract path after googleapis.com (e.g., /v1beta/models/gemini-3-flash:generateContent)
        const googleUrl = new URL(url);
        const pathAfterHost = googleUrl.pathname + googleUrl.search;

        // Build new URL: AI Gateway base + path
        // Note: AI Gateway expects /v1/ not /v1beta/, but it should handle the rewrite
        const gatewayBaseUrl = AI_GATEWAY_BASE_URL.replace(/\/+$/, ''); // Remove trailing slashes
        const newUrl = gatewayBaseUrl + pathAfterHost;

        console.log('[fetch-interceptor] Redirecting Google API request:');
        console.log('[fetch-interceptor]   From:', url);
        console.log('[fetch-interceptor]   To:', newUrl);

        // Update the URL
        url = newUrl;
        if (typeof input === 'string') {
            input = newUrl;
        } else if (input instanceof URL) {
            input = new URL(newUrl);
        } else {
            // Request object - need to create a new one with the new URL
            input = new Request(newUrl, input);
        }
    }

    // === BYOK HEADER MANAGEMENT ===
    // Handle requests to AI Gateway (either direct or redirected)
    const isAIGatewayRequest = url && url.includes('gateway.ai.cloudflare.com');
    const isGoogleAIStudio = url && url.includes('/google-ai-studio');
    const isCustomProvider = url && url.includes('/custom-');
    const needsBYOK = isGoogleAIStudio || isCustomProvider;

    if (isAIGatewayRequest && needsBYOK) {
        const headers = new Headers(init?.headers);

        // Add BYOK authorization header if configured
        if (CF_AIG_AUTHORIZATION) {
            // Remove any existing auth headers so Gateway can inject Provider Key
            // - Authorization: used by OpenAI-compatible SDKs
            // - x-goog-api-key: used by Google's native SDK
            if (headers.has('Authorization')) {
                headers.delete('Authorization');
                console.log('[fetch-interceptor] Removed Authorization header (BYOK mode)');
            }
            if (headers.has('x-goog-api-key')) {
                headers.delete('x-goog-api-key');
                console.log('[fetch-interceptor] Removed x-goog-api-key header (BYOK mode)');
            }
            // Add the cf-aig-authorization header for Gateway authentication
            if (!headers.has('cf-aig-authorization')) {
                headers.set('cf-aig-authorization', CF_AIG_AUTHORIZATION);
                console.log('[fetch-interceptor] Added cf-aig-authorization header (BYOK mode)');
            }
        }

        // Create new init with patched headers
        const patchedInit = {
            ...init,
            headers,
        };

        return originalFetch(input, patchedInit);
    }

    // Pass through all other requests unchanged
    return originalFetch(input, init);
};

console.log('[fetch-interceptor] Installed AI Gateway BYOK interceptor');
if (AI_GATEWAY_BASE_URL && AI_GATEWAY_BASE_URL.includes('/google-ai-studio')) {
    console.log('[fetch-interceptor] URL rewriting enabled: Google API → AI Gateway');
}
if (CF_AIG_AUTHORIZATION) {
    console.log('[fetch-interceptor] BYOK mode enabled (cf-aig-authorization will be injected)');
} else {
    console.log('[fetch-interceptor] BYOK mode disabled (set CF_AIG_AUTHORIZATION to enable)');
}
