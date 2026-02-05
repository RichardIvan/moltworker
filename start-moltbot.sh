#!/bin/bash
# Startup script for Moltbot in Cloudflare Sandbox
# Force rebuild: 2026-02-02T14:51
# This script:
# 1. Restores config from R2 backup if available
# 2. Configures moltbot from environment variables
# 3. Starts a background sync to backup config to R2
# 4. Starts the gateway

set -e

# Check if clawdbot gateway is already running - bail early if so
# Note: CLI is still named "clawdbot" until upstream renames it
if pgrep -f "clawdbot gateway" > /dev/null 2>&1; then
    echo "Moltbot gateway is already running, exiting."
    exit 0
fi

# Paths (clawdbot paths are used internally - upstream hasn't renamed yet)
CONFIG_DIR="/root/.clawdbot"
CONFIG_FILE="$CONFIG_DIR/clawdbot.json"
TEMPLATE_DIR="/root/.clawdbot-templates"
TEMPLATE_FILE="$TEMPLATE_DIR/moltbot.json.template"
BACKUP_DIR="/data/moltbot"

echo "Config directory: $CONFIG_DIR"
echo "Backup directory: $BACKUP_DIR"

# Create config directory
mkdir -p "$CONFIG_DIR"

# ============================================================
# RESTORE FROM R2 BACKUP
# ============================================================
# Check if R2 backup exists by looking for clawdbot.json
# The BACKUP_DIR may exist but be empty if R2 was just mounted
# Note: backup structure is $BACKUP_DIR/clawdbot/ and $BACKUP_DIR/skills/

# Helper function to check if R2 backup is newer than local
should_restore_from_r2() {
    local R2_SYNC_FILE="$BACKUP_DIR/.last-sync"
    local LOCAL_SYNC_FILE="$CONFIG_DIR/.last-sync"
    
    # If no R2 sync timestamp, don't restore
    if [ ! -f "$R2_SYNC_FILE" ]; then
        echo "No R2 sync timestamp found, skipping restore"
        return 1
    fi
    
    # If no local sync timestamp, restore from R2
    if [ ! -f "$LOCAL_SYNC_FILE" ]; then
        echo "No local sync timestamp, will restore from R2"
        return 0
    fi
    
    # Compare timestamps
    R2_TIME=$(cat "$R2_SYNC_FILE" 2>/dev/null)
    LOCAL_TIME=$(cat "$LOCAL_SYNC_FILE" 2>/dev/null)
    
    echo "R2 last sync: $R2_TIME"
    echo "Local last sync: $LOCAL_TIME"
    
    # Convert to epoch seconds for comparison
    R2_EPOCH=$(date -d "$R2_TIME" +%s 2>/dev/null || echo "0")
    LOCAL_EPOCH=$(date -d "$LOCAL_TIME" +%s 2>/dev/null || echo "0")
    
    if [ "$R2_EPOCH" -gt "$LOCAL_EPOCH" ]; then
        echo "R2 backup is newer, will restore"
        return 0
    else
        echo "Local data is newer or same, skipping restore"
        return 1
    fi
}

if [ -f "$BACKUP_DIR/clawdbot/clawdbot.json" ]; then
    if should_restore_from_r2; then
        echo "Restoring from R2 backup at $BACKUP_DIR/clawdbot..."
        cp -a "$BACKUP_DIR/clawdbot/." "$CONFIG_DIR/"
        # Copy the sync timestamp to local so we know what version we have
        cp -f "$BACKUP_DIR/.last-sync" "$CONFIG_DIR/.last-sync" 2>/dev/null || true
        echo "Restored config from R2 backup"
    fi
elif [ -f "$BACKUP_DIR/clawdbot.json" ]; then
    # Legacy backup format (flat structure)
    if should_restore_from_r2; then
        echo "Restoring from legacy R2 backup at $BACKUP_DIR..."
        cp -a "$BACKUP_DIR/." "$CONFIG_DIR/"
        cp -f "$BACKUP_DIR/.last-sync" "$CONFIG_DIR/.last-sync" 2>/dev/null || true
        echo "Restored config from legacy R2 backup"
    fi
elif [ -d "$BACKUP_DIR" ]; then
    echo "R2 mounted at $BACKUP_DIR but no backup data found yet"
else
    echo "R2 not mounted, starting fresh"
fi

# Restore skills from R2 backup if available (only if R2 is newer)
SKILLS_DIR="/root/clawd/skills"
if [ -d "$BACKUP_DIR/skills" ] && [ "$(ls -A $BACKUP_DIR/skills 2>/dev/null)" ]; then
    if should_restore_from_r2; then
        echo "Restoring skills from $BACKUP_DIR/skills..."
        mkdir -p "$SKILLS_DIR"
        cp -a "$BACKUP_DIR/skills/." "$SKILLS_DIR/"
        echo "Restored skills from R2 backup"
    fi
fi

# ============================================================
# RESTORE WORKSPACE PERSONA FILES FROM R2
# ============================================================
# These are the critical persona files (SOUL.md, USER.md, MEMORY.md, etc.)
# plus memory/, tov/, and assets/ directories
WORKSPACE_DIR="/root/clawd"
if [ -d "$BACKUP_DIR/workspace" ] && [ "$(ls -A $BACKUP_DIR/workspace 2>/dev/null)" ]; then
    if should_restore_from_r2; then
        echo "Restoring workspace persona files from R2..."
        mkdir -p "$WORKSPACE_DIR"
        # Restore persona markdown files
        cp -a "$BACKUP_DIR/workspace/"*.md "$WORKSPACE_DIR/" 2>/dev/null || true
        # Restore memory/ (daily notes)
        if [ -d "$BACKUP_DIR/workspace/memory" ]; then
            mkdir -p "$WORKSPACE_DIR/memory"
            cp -a "$BACKUP_DIR/workspace/memory/." "$WORKSPACE_DIR/memory/" 2>/dev/null || true
        fi
        # Restore tov/ (tone of voice)
        if [ -d "$BACKUP_DIR/workspace/tov" ]; then
            mkdir -p "$WORKSPACE_DIR/tov"
            cp -a "$BACKUP_DIR/workspace/tov/." "$WORKSPACE_DIR/tov/" 2>/dev/null || true
        fi
        # Restore assets/ (avatar, images)
        if [ -d "$BACKUP_DIR/workspace/assets" ]; then
            mkdir -p "$WORKSPACE_DIR/assets"
            cp -a "$BACKUP_DIR/workspace/assets/." "$WORKSPACE_DIR/assets/" 2>/dev/null || true
        fi
        echo "Restored persona files from R2 backup"
    fi
fi

# ============================================================
# REPOS DIRECTORY (LOCAL - GitLab is persistence layer)
# ============================================================
# Repos are stored locally for fast git operations.
# Persistence is handled by GitLab via auto-commit/push every 5 minutes.
# On container restart: just reclone and checkout the backup branch.
# This avoids R2 FUSE mount issues that caused git operations to hang.
REPOS_DIR="/root/clawd/repos"

# Remove any existing R2 symlink (migration from old approach)
if [ -L "$REPOS_DIR" ]; then
    echo "Removing old R2 symlink for repos..."
    rm -f "$REPOS_DIR"
fi

# Create local repos directory
mkdir -p "$REPOS_DIR"
echo "Repos directory ready at $REPOS_DIR (GitLab is persistence layer)"

# If config file still doesn't exist, create from template
if [ ! -f "$CONFIG_FILE" ]; then
    echo "No existing config found, initializing from template..."
    if [ -f "$TEMPLATE_FILE" ]; then
        cp "$TEMPLATE_FILE" "$CONFIG_FILE"
    else
        # Create minimal config if template doesn't exist
        cat > "$CONFIG_FILE" << 'EOFCONFIG'
{
  "agents": {
    "defaults": {
      "workspace": "/root/clawd"
    }
  },
  "gateway": {
    "port": 18789,
    "mode": "local"
  }
}
EOFCONFIG
    fi
else
    echo "Using existing config"
fi

# ============================================================
# UPDATE CONFIG FROM ENVIRONMENT VARIABLES
# ============================================================
node << EOFNODE
const fs = require('fs');

const configPath = '/root/.clawdbot/clawdbot.json';
console.log('Updating config at:', configPath);
let config = {};

try {
    config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
} catch (e) {
    console.log('Starting with empty config');
}

// Ensure nested objects exist
config.agents = config.agents || {};
config.agents.defaults = config.agents.defaults || {};
config.agents.defaults.model = config.agents.defaults.model || {};
config.gateway = config.gateway || {};
config.channels = config.channels || {};

// Clean up any broken anthropic provider config from previous runs
// (older versions didn't include required 'name' field)
if (config.models?.providers?.anthropic?.models) {
    const hasInvalidModels = config.models.providers.anthropic.models.some(m => !m.name);
    if (hasInvalidModels) {
        console.log('Removing broken anthropic provider config (missing model names)');
        delete config.models.providers.anthropic;
    }
}

// Clean up invalid openai.api values from R2 backup
// 'openai-chat' is not valid in clawdbot schema - use 'openai-completions' for OpenRouter
if (config.models?.providers?.openai?.api === 'openai-chat') {
    console.log('Fixing invalid openai.api value: openai-chat -> openai-completions');
    config.models.providers.openai.api = 'openai-completions';
}

// Gateway configuration
config.gateway.port = 18789;
config.gateway.mode = 'local';
config.gateway.trustedProxies = ['10.1.0.0'];

// Set gateway token if provided
if (process.env.CLAWDBOT_GATEWAY_TOKEN) {
    config.gateway.auth = config.gateway.auth || {};
    config.gateway.auth.token = process.env.CLAWDBOT_GATEWAY_TOKEN;
}

// Allow insecure auth for dev mode
if (process.env.CLAWDBOT_DEV_MODE === 'true') {
    config.gateway.controlUi = config.gateway.controlUi || {};
    config.gateway.controlUi.allowInsecureAuth = true;
}

// Telegram configuration
if (process.env.TELEGRAM_BOT_TOKEN) {
    config.channels.telegram = config.channels.telegram || {};
    config.channels.telegram.botToken = process.env.TELEGRAM_BOT_TOKEN;
    config.channels.telegram.enabled = true;
    const telegramDmPolicy = process.env.TELEGRAM_DM_POLICY || 'pairing';
    config.channels.telegram.dmPolicy = telegramDmPolicy;
    if (process.env.TELEGRAM_DM_ALLOW_FROM) {
        // Explicit allowlist: "123,456,789" → ['123', '456', '789']
        config.channels.telegram.allowFrom = process.env.TELEGRAM_DM_ALLOW_FROM.split(',');
    } else if (telegramDmPolicy === 'open') {
        // "open" policy requires allowFrom: ["*"]
        config.channels.telegram.allowFrom = ['*'];
    }
}

// Discord configuration
// Note: Discord uses nested dm.policy, not flat dmPolicy like Telegram
// See: https://github.com/moltbot/moltbot/blob/v2026.1.24-1/src/config/zod-schema.providers-core.ts#L147-L155
if (process.env.DISCORD_BOT_TOKEN) {
    config.channels.discord = config.channels.discord || {};
    config.channels.discord.token = process.env.DISCORD_BOT_TOKEN;
    config.channels.discord.enabled = true;
    const discordDmPolicy = process.env.DISCORD_DM_POLICY || 'pairing';
    config.channels.discord.dm = config.channels.discord.dm || {};
    config.channels.discord.dm.policy = discordDmPolicy;
    // "open" policy requires allowFrom: ["*"]
    if (discordDmPolicy === 'open') {
        config.channels.discord.dm.allowFrom = ['*'];
    }
}

// Slack configuration
if (process.env.SLACK_BOT_TOKEN && process.env.SLACK_APP_TOKEN) {
    config.channels.slack = config.channels.slack || {};
    config.channels.slack.botToken = process.env.SLACK_BOT_TOKEN;
    config.channels.slack.appToken = process.env.SLACK_APP_TOKEN;
    config.channels.slack.enabled = true;
}

// Base URL override (e.g., for Cloudflare AI Gateway)
// Usage: Set AI_GATEWAY_BASE_URL or ANTHROPIC_BASE_URL to your endpoint like:
//   https://gateway.ai.cloudflare.com/v1/{account_id}/{gateway_id}/anthropic
//   https://gateway.ai.cloudflare.com/v1/{account_id}/{gateway_id}/openai
//   https://gateway.ai.cloudflare.com/v1/{account_id}/{gateway_id}/openrouter
//   https://gateway.ai.cloudflare.com/v1/{account_id}/{gateway_id}/fireworks (custom provider)
//   https://gateway.ai.cloudflare.com/v1/{account_id}/{gateway_id}/google-ai-studio
const baseUrl = (process.env.AI_GATEWAY_BASE_URL || process.env.ANTHROPIC_BASE_URL || '').replace(/\/+$/, '');
const isOpenAI = baseUrl.endsWith('/openai');
const isOpenRouter = baseUrl.endsWith('/openrouter');
const isFireworks = baseUrl.includes('fireworks.ai') || baseUrl.endsWith('/fireworks') || baseUrl.endsWith('/custom-fireworks');
const isGoogleAIStudio = baseUrl.endsWith('/google-ai-studio');

if (isOpenAI) {
    // Create custom openai provider config with baseUrl override
    // Omit apiKey so moltbot falls back to OPENAI_API_KEY env var
    console.log('Configuring OpenAI provider with base URL:', baseUrl);
    config.models = config.models || {};
    config.models.providers = config.models.providers || {};
    config.models.providers.openai = {
        baseUrl: baseUrl,
        api: 'openai-responses',
        models: [
            { id: 'gpt-5.2', name: 'GPT-5.2', contextWindow: 200000 },
            { id: 'gpt-5', name: 'GPT-5', contextWindow: 200000 },
            { id: 'gpt-4.5-preview', name: 'GPT-4.5 Preview', contextWindow: 128000 },
        ]
    };
    // Add models to the allowlist so they appear in /models
    config.agents.defaults.models = config.agents.defaults.models || {};
    config.agents.defaults.models['openai/gpt-5.2'] = { alias: 'GPT-5.2' };
    config.agents.defaults.models['openai/gpt-5'] = { alias: 'GPT-5' };
    config.agents.defaults.models['openai/gpt-4.5-preview'] = { alias: 'GPT-4.5' };
    config.agents.defaults.model.primary = 'openai/gpt-5.2';
} else if (isGoogleAIStudio) {
    // Google AI Studio via Cloudflare AI Gateway Unified API (OpenAI-compatible)
    // 
    // IMPORTANT: The /google-ai-studio route uses Google's native API format.
    // For OpenAI-compatible requests, use the /compat endpoint instead:
    //   Base URL: https://gateway.ai.cloudflare.com/v1/{account}/{gateway}/compat
    //   Model format: google-ai-studio/{model}
    //
    // We auto-convert to /compat by replacing /google-ai-studio with /compat
    const compatBaseUrl = baseUrl.replace('/google-ai-studio', '/compat');
    console.log('Configuring Google AI Studio provider with Unified API:', compatBaseUrl);
    config.models = config.models || {};
    config.models.providers = config.models.providers || {};
    config.models.providers.openai = {
        baseUrl: compatBaseUrl,
        api: 'openai-completions',
        // API key from env (set via AI_GATEWAY_API_KEY secret → mapped to OPENAI_API_KEY)
        // Fetch interceptor removes this when CF_AIG_AUTHORIZATION is set (BYOK mode)
        apiKey: process.env.OPENAI_API_KEY,
        // Model IDs must include provider prefix for /compat endpoint
        models: [
            { id: 'google-ai-studio/gemini-3-flash-preview', name: 'Gemini 3 Flash Preview', contextWindow: 1000000 },
            { id: 'google-ai-studio/gemini-2.5-flash', name: 'Gemini 2.5 Flash', contextWindow: 1000000 },
            { id: 'google-ai-studio/gemini-2.5-pro', name: 'Gemini 2.5 Pro', contextWindow: 1000000 },
        ]
    };
    // Add models to the allowlist so they appear in /models
    config.agents.defaults.models = config.agents.defaults.models || {};
    config.agents.defaults.models['openai/google-ai-studio/gemini-3-flash-preview'] = { alias: 'Gemini 3 Flash' };
    config.agents.defaults.models['openai/google-ai-studio/gemini-2.5-flash'] = { alias: 'Gemini 2.5 Flash' };
    config.agents.defaults.models['openai/google-ai-studio/gemini-2.5-pro'] = { alias: 'Gemini 2.5 Pro' };
    config.agents.defaults.model.primary = 'openai/google-ai-studio/gemini-3-flash-preview';
} else if (isFireworks) {
    // Fireworks.ai endpoint (OpenAI-compatible format)
    // Direct: https://api.fireworks.ai/inference/v1
    // Via AI Gateway Custom Provider: https://gateway.ai.cloudflare.com/v1/{account}/{gateway}/fireworks
    console.log('Configuring Fireworks provider with base URL:', baseUrl);
    config.models = config.models || {};
    config.models.providers = config.models.providers || {};
    config.models.providers.openai = {
        baseUrl: baseUrl,
        api: 'openai-completions',
        // API key from env (set via AI_GATEWAY_API_KEY secret → mapped to OPENAI_API_KEY)
        // Fetch interceptor removes this when CF_AIG_AUTHORIZATION is set (BYOK mode)
        apiKey: process.env.OPENAI_API_KEY,
        // Cost tracking via cf-aig-custom-cost header (injected by fetch-cost-interceptor.cjs)
        // Fireworks pricing: $0.56/1M input, $1.68/1M output
        models: [
            { id: 'accounts/fireworks/models/deepseek-v3p2', name: 'DeepSeek V3.2', contextWindow: 163840 },
            { id: 'accounts/fireworks/models/kimi-k2p5', name: 'Kimi K2.5', contextWindow: 262144 },
            { id: 'accounts/fireworks/models/qwen3-235b-a22b', name: 'Qwen 3 235B', contextWindow: 131072 },
        ]
    };
    // Add models to the allowlist so they appear in /models
    config.agents.defaults.models = config.agents.defaults.models || {};
    config.agents.defaults.models['openai/accounts/fireworks/models/deepseek-v3p2'] = { alias: 'DeepSeek V3.2' };
    config.agents.defaults.models['openai/accounts/fireworks/models/kimi-k2p5'] = { alias: 'Kimi K2.5' };
    config.agents.defaults.models['openai/accounts/fireworks/models/qwen3-235b-a22b'] = { alias: 'Qwen 3' };
    config.agents.defaults.model.primary = 'openai/accounts/fireworks/models/deepseek-v3p2';
} else if (isOpenRouter) {
    // OpenRouter endpoint (OpenAI-compatible format)
    // Omit apiKey so moltbot falls back to OPENAI_API_KEY env var
    console.log('Configuring OpenRouter provider with base URL:', baseUrl);
    config.models = config.models || {};
    config.models.providers = config.models.providers || {};
    config.models.providers.openai = {
        baseUrl: baseUrl,
        api: 'openai-completions',
        models: [
            { id: 'deepseek/deepseek-v3.2', name: 'DeepSeek V3.2', contextWindow: 163840 },
            { id: 'moonshotai/kimi-k2.5', name: 'Kimi 2.5', contextWindow: 262144 },
            { id: 'google/gemma-3-27b-it', name: 'Gemma 3 27B', contextWindow: 131072 },
        ]
    };
    // Add models to the allowlist so they appear in /models
    config.agents.defaults.models = config.agents.defaults.models || {};
    config.agents.defaults.models['openai/deepseek/deepseek-v3.2'] = { alias: 'DeepSeek V3.2' };
    config.agents.defaults.models['openai/moonshotai/kimi-k2.5'] = { alias: 'Kimi 2.5' };
    config.agents.defaults.models['openai/google/gemma-3-27b-it'] = { alias: 'Gemma 3' };
    config.agents.defaults.model.primary = 'openai/deepseek/deepseek-v3.2';
} else if (baseUrl) {
    console.log('Configuring Anthropic provider with base URL:', baseUrl);
    config.models = config.models || {};
    config.models.providers = config.models.providers || {};
    const providerConfig = {
        baseUrl: baseUrl,
        api: 'anthropic-messages',
        models: [
            { id: 'claude-opus-4-5-20251101', name: 'Claude Opus 4.5', contextWindow: 200000 },
            { id: 'claude-sonnet-4-5-20250929', name: 'Claude Sonnet 4.5', contextWindow: 200000 },
            { id: 'claude-haiku-4-5-20251001', name: 'Claude Haiku 4.5', contextWindow: 200000 },
        ]
    };
    // Include API key in provider config if set (required when using custom baseUrl)
    if (process.env.ANTHROPIC_API_KEY) {
        providerConfig.apiKey = process.env.ANTHROPIC_API_KEY;
    }
    config.models.providers.anthropic = providerConfig;
    // Add models to the allowlist so they appear in /models
    config.agents.defaults.models = config.agents.defaults.models || {};
    config.agents.defaults.models['anthropic/claude-opus-4-5-20251101'] = { alias: 'Opus 4.5' };
    config.agents.defaults.models['anthropic/claude-sonnet-4-5-20250929'] = { alias: 'Sonnet 4.5' };
    config.agents.defaults.models['anthropic/claude-haiku-4-5-20251001'] = { alias: 'Haiku 4.5' };
    config.agents.defaults.model.primary = 'anthropic/claude-opus-4-5-20251101';
} else {
    // Default to Anthropic without custom base URL (uses built-in pi-ai catalog)
    config.agents.defaults.model.primary = 'anthropic/claude-opus-4-5';
}

// Write updated config
fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
console.log('Configuration updated successfully');
console.log('Config:', JSON.stringify(config, null, 2));
EOFNODE

# ============================================================
# GITLAB/GIT SETUP
# ============================================================
if [ -n "$GITLAB_TOKEN" ]; then
    echo "Configuring Git for GitLab..."
    
    # Configure git identity
    git config --global user.name "${GIT_USER_NAME:-OpenClaw Agent}"
    git config --global user.email "${GIT_USER_EMAIL:-agent@openclaw.local}"
    
    # Configure git credentials for GitLab (oauth2 token format)
    git config --global credential.helper store
    echo "https://oauth2:${GITLAB_TOKEN}@gitlab.com" > ~/.git-credentials
    chmod 600 ~/.git-credentials
    
    # Authenticate glab CLI (glab is installed in Docker image)
    echo "$GITLAB_TOKEN" | glab auth login --stdin --hostname gitlab.com 2>/dev/null || true
    
    # Clone repository if URL provided and not already cloned
    # Note: Agent clones manually, R2 persists across restarts
    # This just ensures credentials are ready for when the agent needs them
    
    echo "GitLab setup complete!"
fi

# ============================================================
# START GATEWAY
# ============================================================
# Note: R2 backup sync is handled by the Worker's cron trigger
echo "Starting Moltbot Gateway..."
echo "Gateway will be available on port 18789"

# Clean up stale lock files
rm -f /tmp/clawdbot-gateway.lock 2>/dev/null || true
rm -f "$CONFIG_DIR/gateway.lock" 2>/dev/null || true

BIND_MODE="lan"
echo "Dev mode: ${CLAWDBOT_DEV_MODE:-false}, Bind mode: $BIND_MODE"

# Enable fetch interceptor for AI Gateway cost tracking
# This adds the cf-aig-custom-cost header to requests going through custom providers
export NODE_OPTIONS="--require /usr/local/lib/fetch-cost-interceptor.cjs"

if [ -n "$CLAWDBOT_GATEWAY_TOKEN" ]; then
    echo "Starting gateway with token auth..."
    exec clawdbot gateway --port 18789 --verbose --allow-unconfigured --bind "$BIND_MODE" --token "$CLAWDBOT_GATEWAY_TOKEN"
else
    echo "Starting gateway with device pairing (no token)..."
    exec clawdbot gateway --port 18789 --verbose --allow-unconfigured --bind "$BIND_MODE"
fi
