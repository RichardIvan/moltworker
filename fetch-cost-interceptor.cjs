/**
 * Fetch interceptor to add AI Gateway cost tracking headers
 * 
 * This script patches the global fetch to add the cf-aig-custom-cost header
 * for requests to Cloudflare AI Gateway.
 * 
 * Usage: NODE_OPTIONS="--require /path/to/fetch-cost-interceptor.cjs" node app.js
 */

// Fireworks DeepSeek V3.2 serverless pricing
// https://fireworks.ai/models/fireworks/deepseek-v3p2
const FIREWORKS_COST = {
    per_token_in: 0.00000056,   // $0.56 / 1M tokens
    per_token_out: 0.00000168,  // $1.68 / 1M tokens
};

const originalFetch = globalThis.fetch;

globalThis.fetch = async function patchedFetch(input, init) {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;

    // Only intercept requests to AI Gateway custom providers
    if (url && url.includes('gateway.ai.cloudflare.com') && url.includes('/custom-')) {
        const headers = new Headers(init?.headers);

        // Add cost tracking header if not already present
        if (!headers.has('cf-aig-custom-cost')) {
            headers.set('cf-aig-custom-cost', JSON.stringify(FIREWORKS_COST));
            console.log('[fetch-interceptor] Added cf-aig-custom-cost header for:', url.split('/').slice(0, 7).join('/') + '/...');
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

console.log('[fetch-interceptor] Installed AI Gateway cost tracking interceptor');
