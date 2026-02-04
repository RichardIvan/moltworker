/**
 * Fetch interceptor to add AI Gateway headers
 * 
 * This script patches the global fetch to add:
 * - cf-aig-custom-cost: Cost tracking for custom providers
 * - cf-aig-authorization: BYOK mode (API key stored in CF dashboard)
 * 
 * Usage: NODE_OPTIONS="--require /path/to/fetch-cost-interceptor.cjs" node app.js
 * 
 * Environment variables:
 * - CF_AIG_AUTHORIZATION: Token for BYOK mode (optional)
 */

// Fireworks DeepSeek V3.2 serverless pricing
// https://fireworks.ai/models/fireworks/deepseek-v3p2
const FIREWORKS_COST = {
    per_token_in: 0.00000056,   // $0.56 / 1M tokens
    per_token_out: 0.00000168,  // $1.68 / 1M tokens
};

// BYOK authorization token (set via environment variable)
const CF_AIG_AUTHORIZATION = process.env.CF_AIG_AUTHORIZATION;

const originalFetch = globalThis.fetch;

globalThis.fetch = async function patchedFetch(input, init) {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;

    // Only intercept requests to AI Gateway custom providers
    if (url && url.includes('gateway.ai.cloudflare.com') && url.includes('/custom-')) {
        const headers = new Headers(init?.headers);

        // Add cost tracking header if not already present
        if (!headers.has('cf-aig-custom-cost')) {
            headers.set('cf-aig-custom-cost', JSON.stringify(FIREWORKS_COST));
            console.log('[fetch-interceptor] Added cf-aig-custom-cost header');
        }

        // Add BYOK authorization header if configured and not already present
        if (CF_AIG_AUTHORIZATION && !headers.has('cf-aig-authorization')) {
            headers.set('cf-aig-authorization', CF_AIG_AUTHORIZATION);
            console.log('[fetch-interceptor] Added cf-aig-authorization header (BYOK mode)');
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

console.log('[fetch-interceptor] Installed AI Gateway interceptor');
if (CF_AIG_AUTHORIZATION) {
    console.log('[fetch-interceptor] BYOK mode enabled (cf-aig-authorization will be injected)');
} else {
    console.log('[fetch-interceptor] BYOK mode disabled (set CF_AIG_AUTHORIZATION to enable)');
}
