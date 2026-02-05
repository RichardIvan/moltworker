/**
 * Fetch interceptor for AI Gateway BYOK (Bring Your Own Key) mode
 * 
 * BYOK Flow:
 * 1. Clawdbot validates config using placeholder API key
 * 2. Clawdbot sends request with Authorization: Bearer BYOK-PLACEHOLDER
 * 3. This interceptor REMOVES the Authorization header
 * 4. This interceptor ADDS cf-aig-authorization header (Gateway auth)
 * 5. Gateway receives request with NO Authorization → injects Provider Key
 * 6. Provider (Fireworks, Google AI Studio) receives the real API key
 * 
 * Usage: NODE_OPTIONS="--require /path/to/fetch-cost-interceptor.cjs" node app.js
 * 
 * Environment variables:
 * - CF_AIG_AUTHORIZATION: API token for AI Gateway authentication (required for BYOK)
 */

// BYOK authorization token (set via environment variable)
const CF_AIG_AUTHORIZATION = process.env.CF_AIG_AUTHORIZATION;

const originalFetch = globalThis.fetch;

globalThis.fetch = async function patchedFetch(input, init) {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;

    // Only intercept requests to AI Gateway (custom providers and google-ai-studio for BYOK)
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
if (CF_AIG_AUTHORIZATION) {
    console.log('[fetch-interceptor] BYOK mode enabled (cf-aig-authorization will be injected)');
} else {
    console.log('[fetch-interceptor] BYOK mode disabled (set CF_AIG_AUTHORIZATION to enable)');
}
