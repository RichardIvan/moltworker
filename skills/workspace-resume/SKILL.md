---
name: Workspace Resume
description: Resume work on effortlessthai project, handling container restarts automatically
---

# Workspace Resume

When user says **"start working"** or **"resume"**, follow this sequence:

## 1. Check Current State

```bash
ls -la /tmp/effortlessthai 2>/dev/null && git -C /tmp/effortlessthai status 2>/dev/null
```

**If exists and clean:** Skip to step 5 (verify backup is running).

**If missing or corrupted:** Continue to step 2.

## 2. Find Last Working Branch

Find recent commits by **Bro** (your git identity) to determine what branch you were working on:

```bash
glab api "projects/little-bits%2Feffortlessthai/repository/commits?per_page=10" | jq -r '.[] | select(.author_name == "Bro") | "\(.committed_date) - \(.message) - refs: \(.parent_ids[0][:8])"' | head -5
```

Or check branches with your recent commits:
```bash
glab api "projects/little-bits%2Feffortlessthai/repository/branches?per_page=20" | jq -r '.[] | select(.commit.author_name == "Bro") | "\(.name) - \(.commit.committed_date)"' | head -5
```

Or check for your open MRs:
```bash
glab mr list --repo little-bits/effortlessthai --author=@me --state=opened
```

**Pick the branch with your most recent commit.**

## 3. Clone Repository

```bash
rm -rf /tmp/effortlessthai
git clone https://gitlab.com/little-bits/effortlessthai.git /tmp/effortlessthai
cd /tmp/effortlessthai
```

## 4. Checkout the Working Branch

**Use the branch you found in step 2**, for example:

```bash
cd /tmp/effortlessthai
git fetch origin feat/mdx-blog-setup && git checkout feat/mdx-blog-setup
```

Or fallback to backup branch:
```bash
git fetch origin backup/work-in-progress 2>/dev/null && git checkout backup/work-in-progress || echo "No WIP branch, starting fresh on main"
```

## 4. Start Auto-Backup (if not running)

Check if backup process is running:
```bash
ps aux | grep -v grep | grep "effortlessthai" | grep -E "(sleep|git)"
```

If NOT running, start it:
```bash
cd /tmp/effortlessthai && while true; do git add . && git commit --allow-empty -m "Auto-backup $(date +%H:%M)" && git push origin HEAD:backup/work-in-progress --force; sleep 300; done &
```

## 5. Report Status

Tell the user:
- ✅ Workspace ready at `/tmp/effortlessthai`
- ✅ Auto-backup running (every 5 minutes)
- ✅ Ready to work

Then ask: **"What would you like to work on?"**

---

## Recovery Commands

**Force immediate backup:**
```bash
cd /tmp/effortlessthai && git add . && git commit -m "Manual backup" && git push origin HEAD:backup/work-in-progress --force
```

**Check backup log:**
```bash
ps aux | grep effortlessthai
```

**View recent commits:**
```bash
cd /tmp/effortlessthai && git log --oneline -5
```
