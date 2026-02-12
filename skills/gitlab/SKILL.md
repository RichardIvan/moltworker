---
name: gitlab
description: "Interact with GitLab using the `glab` CLI. Use `glab mr`, `glab issue`, `glab ci`, and `glab api` for merge requests, issues, CI pipelines, and advanced queries."
---

# GitLab Skill

Use the `glab` CLI to interact with GitLab. Always specify `--repo owner/repo` when not in a git directory, or use URLs directly.

## Merge Requests

Check CI/pipeline status on an MR:
```bash
glab ci status --repo owner/repo
```

List recent pipeline runs:
```bash
glab ci list --repo owner/repo --per-page 10
```

View a pipeline and see which jobs failed:
```bash
glab ci view <pipeline-id> --repo owner/repo
```

View logs for a specific job:
```bash
glab ci trace <job-id> --repo owner/repo
```

## API for Advanced Queries

The `glab api` command is useful for accessing data not available through other subcommands.

Get MR with specific fields:
```bash
glab api projects/:id/merge_requests/55 --jq '.title, .state, .author.username'
```

## JSON Output

Most commands support `--output json` for structured output. You can use `--jq` or pipe to `jq` to filter:

```bash
glab mr list --repo owner/repo --output json | jq '.[] | "\(.iid): \(.title)"'
```
