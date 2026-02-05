/**
 * Fetch interceptor for AI Gateway custom providers
 * 
 * This script patches global fetch to enable BYOK (Bring Your Own Key) mode:
 * 
 * BYOK Flow:
 * 1. Clawdbot validates config using placeholder API key
 * 2. Clawdbot sends request with Authorization: Bearer BYOK-PLACEHOLDER
 * 3. This interceptor REMOVES the Authorization header
 * 4. This interceptor ADDS cf-aig-authorization header (Gateway auth)
 * 5. Gateway receives request with NO Authorization → injects Provider Key
 * 6. Provider (Fireworks, Google AI Studio) receives the real API key
 * 
 * Headers injected:
 * - cf-aig-custom-cost: Cost tracking for AI Gateway dashboard
 * - cf-aig-authorization: Authenticates to AI Gateway (enables BYOK)
 * 
 * Usage: NODE_OPTIONS="--require /path/to/fetch-cost-interceptor.cjs" node app.js
 * 
 * Environment variables:
 * - CF_AIG_AUTHORIZATION: API token for AI Gateway authentication (required for BYOK)
 */

// Provider pricing for cost tracking in AI Gateway dashboard
// Set to 0 for free tier - Gateway will still track token usage
//
// Fireworks DeepSeek V3.2 serverless pricing
// https://fireworks.ai/models/fireworks/deepseek-v3p2
const FIREWORKS_COST = {
    per_token_in: 0.00000056,   // $0.56 / 1M tokens
    per_token_out: 0.00000168,  // $1.68 / 1M tokens
};

// Google AI Studio Gemini 3 Flash Preview pricing
// https://ai.google.dev/pricing
// Note: Set to 0 if using free tier (tokens still tracked)
const GEMINI_COST = {
    per_token_in: 0.0000005,    // $0.50 / 1M tokens
    per_token_out: 0.000003,    // $3.00 / 1M tokens
};

// Free tier - set this if you're on free quota
// Tokens will still be tracked, just no cost
const FREE_TIER_COST = {
    per_token_in: 0,
    per_token_out: 0,
};

// BYOK authorization token (set via environment variable)
const CF_AIG_AUTHORIZATION = process.env.CF_AIG_AUTHORIZATION;

const originalFetch = globalThis.fetch;

globalThis.fetch = async function patchedFetch(input, init) {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;

    // Only intercept requests to AI Gateway (custom providers and compat/google-ai-studio for BYOK)
    const isAIGatewayRequest = url && url.includes('gateway.ai.cloudflare.com');
    // /compat is the Unified API endpoint for OpenAI-compatible requests to any provider
    const isCompatEndpoint = url && url.includes('/compat');
    const isGoogleAIStudio = url && url.includes('/google-ai-studio');
    const isCustomProvider = url && url.includes('/custom-');
    const needsBYOK = isGoogleAIStudio || isCustomProvider || isCompatEndpoint;

    if (isAIGatewayRequest && needsBYOK) {
        const headers = new Headers(init?.headers);

        // Select cost based on provider
        // Change to FREE_TIER_COST if using free quota
        // Note: /compat endpoint is currently only used for Google AI Studio
        const isGeminiRequest = isGoogleAIStudio || isCompatEndpoint;
        const cost = isGeminiRequest ? GEMINI_COST : FIREWORKS_COST;

        // Add cost tracking header if not already present
        if (!headers.has('cf-aig-custom-cost')) {
            headers.set('cf-aig-custom-cost', JSON.stringify(cost));
            console.log('[fetch-interceptor] Added cf-aig-custom-cost header:', isGeminiRequest ? 'Gemini' : 'Fireworks');
        }

        // Add BYOK authorization header if configured
        if (CF_AIG_AUTHORIZATION) {
            // Remove any existing Authorization header so Gateway can inject Provider Key
            if (headers.has('Authorization')) {
                headers.delete('Authorization');
                console.log('[fetch-interceptor] Removed Authorization header (BYOK mode - Gateway will inject Provider Key)');
            }
            // Add the cf-aig-authorization header for Gateway authentication
            if (!headers.has('cf-aig-authorization')) {
                headers.set('cf-aig-authorization', CF_AIG_AUTHORIZATION);
                console.log('[fetch-interceptor] Added cf-aig-authorization header (BYOK mode)');
            }
        }

        // For Gemini requests, strip OpenAI-specific parameters that aren't supported
        let patchedBody = init?.body;
        if (isGeminiRequest && init?.body && typeof init.body === 'string') {
            try {
                const body = JSON.parse(init.body);
                // List of OpenAI-specific parameters not supported by Gemini
                const unsupportedParams = ['store', 'metadata', 'stream_options', 'service_tier'];
                let modified = false;
                for (const param of unsupportedParams) {
                    if (param in body) {
                        delete body[param];
                        modified = true;
                    }
                }
                if (modified) {
                    patchedBody = JSON.stringify(body);
                    console.log('[fetch-interceptor] Stripped unsupported OpenAI params for Gemini');
                }
            } catch (e) {
                // Not JSON or parsing failed, pass through unchanged
            }
        }

        // Create new init with patched headers and body
        const patchedInit = {
            ...init,
            headers,
            body: patchedBody,
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
