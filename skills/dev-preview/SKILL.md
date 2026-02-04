---
name: dev-preview
description: Start a dev server and expose it via Cloudflare Tunnel for live preview
---

# Dev Preview Skill

Expose a local development server via Cloudflare Tunnel so the user can preview changes in their browser.

## Quick Start

```bash
# 1. Install dependencies (if needed)
cd /root/clawd/repos/gitlab/effortlessthai
npm install

# 2. Start dev server in background
npm run dev &

# 3. Wait for server to start
sleep 10

# 4. Start tunnel (this will output a public URL)
cloudflared tunnel --url http://localhost:3000
```

## The tunnel will output something like:
```
Your quick tunnel has been created! Visit it at:
https://random-words-here.trycloudflare.com
```

**Give this URL to the user** so they can preview the changes!

## Port Reference

| Framework | Default Port | Command |
|-----------|-------------|---------|
| Next.js | 3000 | `npm run dev` |
| Vite | 5173 | `npm run dev` |
| Create React App | 3000 | `npm start` |

## Testing Without Tunnel

For quick self-tests (no user preview needed):

```bash
# Start server in background
npm run dev &
sleep 10

# Check if server responds
curl -I http://localhost:3000

# Check specific page
curl http://localhost:3000/api/health
```

## Important Notes

1. **Background processes**: Use `&` to run server in background
2. **Wait for startup**: Always `sleep 10` after starting server
3. **Kill when done**: `pkill -f "npm run dev"` to stop server
4. **Tunnel is temporary**: URL only works while tunnel is running

## Self-Verification with Browser

**You have a browser tool!** Use the tunnel URL to visually verify your own work:

```bash
# 1. Start dev server in background
npm run dev &
sleep 10

# 2. Start tunnel and capture the URL
cloudflared tunnel --url http://localhost:3000 2>&1 | grep -o 'https://[^ ]*\.trycloudflare\.com' | head -1
```

Then use your `browser` tool to:
1. Navigate to the tunnel URL
2. Take screenshots of pages you modified
3. Verify UI looks correct
4. Check for console errors

**Example browser verification:**
```
browser navigate="https://random-words.trycloudflare.com"
browser screenshot  # Capture what you see
browser navigate="https://random-words.trycloudflare.com/pricing"
browser screenshot  # Verify pricing page
```

## Full Workflow Example

```bash
# Full workflow: make changes, build, test, verify visually
cd /root/clawd/repos/gitlab/effortlessthai

# 1. Build to check for errors
npm run build

# 2. Start dev server
npm run dev &
sleep 10

# 3. Quick API test
curl -I http://localhost:3000

# 4. Start tunnel for visual verification
cloudflared tunnel --url http://localhost:3000
# Capture the https://xxx.trycloudflare.com URL

# 5. Use browser tool to navigate and screenshot
# 6. Share URL with user if they want to see it too
```
