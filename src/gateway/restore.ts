import type { Sandbox } from '@cloudflare/sandbox';
import type { MoltbotEnv } from '../types';
import { R2_MOUNT_PATH } from '../config';
import { mountR2Storage } from './r2';
import { waitForProcess } from './utils';

export interface RestoreResult {
    success: boolean;
    lastSync?: string;
    error?: string;
    details?: string;
}

/**
 * Restore moltbot config from R2 to container.
 * This is the reverse of syncToR2() and should be called on container boot.
 * 
 * This function:
 * 1. Mounts R2 if not already mounted
 * 2. Verifies R2 has a valid backup (.last-sync exists)
 * 3. Runs rsync to copy config from R2 to container
 * 
 * Restored paths:
 * - R2/clawdbot/         → /root/.clawdbot/        (gateway config + cron jobs)
 * - R2/skills/           → /root/clawd/skills/     (custom skills)
 * - R2/workspace/*.md    → /root/clawd/            (persona files: IDENTITY.md, PLAN.md, etc.)
 * - R2/workspace/memory/ → /root/clawd/memory/     (daily notes)
 * - R2/workspace/tov/    → /root/clawd/tov/        (tone of voice)
 * - R2/workspace/assets/ → /root/clawd/assets/     (avatar, images)
 * 
 * @param sandbox - The sandbox instance
 * @param env - Worker environment bindings
 * @returns RestoreResult with success status and optional error details
 */
export async function restoreFromR2(sandbox: Sandbox, env: MoltbotEnv): Promise<RestoreResult> {
    // Check if R2 is configured
    if (!env.R2_ACCESS_KEY_ID || !env.R2_SECRET_ACCESS_KEY || !env.CF_ACCOUNT_ID) {
        return { success: false, error: 'R2 storage is not configured' };
    }

    // Mount R2 if not already mounted
    const mounted = await mountR2Storage(sandbox, env);
    if (!mounted) {
        return { success: false, error: 'Failed to mount R2 storage' };
    }

    // Check if R2 has a valid backup by looking for .last-sync timestamp
    try {
        const checkProc = await sandbox.startProcess(`test -f ${R2_MOUNT_PATH}/.last-sync && cat ${R2_MOUNT_PATH}/.last-sync`);
        await waitForProcess(checkProc, 5000);
        const checkLogs = await checkProc.getLogs();
        const lastSync = checkLogs.stdout?.trim();

        if (!lastSync || !lastSync.match(/^\d{4}-\d{2}-\d{2}/)) {
            return {
                success: false,
                error: 'No valid backup found in R2',
                details: 'R2/.last-sync is missing or invalid. This may be a fresh deployment.',
            };
        }

        console.log('[Restore] Found R2 backup dated:', lastSync);
    } catch (err) {
        return {
            success: false,
            error: 'Failed to verify R2 backup',
            details: err instanceof Error ? err.message : 'Unknown error',
        };
    }

    // Ensure destination directories exist
    const mkdirCmd = `mkdir -p /root/.clawdbot /root/clawd /root/clawd/skills /root/clawd/memory /root/clawd/tov /root/clawd/assets`;

    // Restore *.md files from workspace root (not subdirs)
    // Using find + cp to restore only files in the root (not subdirs like memory/)
    const restoreMdFiles = `find ${R2_MOUNT_PATH}/workspace -maxdepth 1 -name '*.md' -type f -exec cp {} /root/clawd/ \\; 2>/dev/null || true`;

    // Run rsync to restore config from R2
    // Note: Use --no-times because s3fs doesn't support setting timestamps
    // We use --ignore-existing=false (default) to overwrite local files with R2 backup
    const restoreCmd = `${mkdirCmd} && rsync -r --no-times ${R2_MOUNT_PATH}/clawdbot/ /root/.clawdbot/ 2>/dev/null || true && rsync -r --no-times ${R2_MOUNT_PATH}/skills/ /root/clawd/skills/ 2>/dev/null || true && ${restoreMdFiles} && rsync -r --no-times ${R2_MOUNT_PATH}/workspace/memory/ /root/clawd/memory/ 2>/dev/null || true && rsync -r --no-times ${R2_MOUNT_PATH}/workspace/tov/ /root/clawd/tov/ 2>/dev/null || true && rsync -r --no-times ${R2_MOUNT_PATH}/workspace/assets/ /root/clawd/assets/ 2>/dev/null || true`;

    try {
        const proc = await sandbox.startProcess(restoreCmd);
        await waitForProcess(proc, 30000); // 30 second timeout for restore

        // Read the last-sync timestamp for reporting
        const timestampProc = await sandbox.startProcess(`cat ${R2_MOUNT_PATH}/.last-sync`);
        await waitForProcess(timestampProc, 5000);
        const timestampLogs = await timestampProc.getLogs();
        const lastSync = timestampLogs.stdout?.trim();

        console.log('[Restore] Completed. Restored from backup dated:', lastSync);
        return { success: true, lastSync };
    } catch (err) {
        return {
            success: false,
            error: 'Restore error',
            details: err instanceof Error ? err.message : 'Unknown error',
        };
    }
}
