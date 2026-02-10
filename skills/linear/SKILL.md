---
name: linear
description: "Manage Linear issues, projects, and teams using the `linear` CLI. Create, list, update issues, track projects, and query the Linear GraphQL API."
---

# Linear CLI Skill

Use the `linear` CLI to manage Linear project management from the command line. Authenticated via `LINEAR_API_KEY` env var.

## Issues

List assigned issues:
```bash
linear issue list
```

View a specific issue:
```bash
linear issue view ENG-123
```

Create an issue:
```bash
linear issue create --title "Fix login bug" --description "Users can't log in with SSO"
```

Update issue status:
```bash
linear issue update ENG-123 --status "In Progress"
```

Start working on an issue (creates branch, sets status):
```bash
linear issue start ENG-123
```

## Projects

List projects:
```bash
linear project list
```

## Teams

List teams:
```bash
linear team list
```

## Discovering Options

Every command supports `--help` for detailed flags:
```bash
linear --help
linear issue --help
linear issue list --help
linear issue create --help
```

## GraphQL API (Fallback)

For operations not covered by the CLI, use the raw API:
```bash
# Simple query
linear api '{ viewer { id name email } }'

# Query with variables
linear api 'query($teamId: String!) { team(id: $teamId) { name } }' --variable teamId=abc123

# Pipe to jq for filtering
linear api '{ issues(first: 5) { nodes { identifier title } } }' | jq '.data.issues.nodes[].title'
```

Check the schema for available types:
```bash
linear schema -o "${TMPDIR:-/tmp}/linear-schema.graphql"
grep -A 30 "^type Issue " "${TMPDIR:-/tmp}/linear-schema.graphql"
```
