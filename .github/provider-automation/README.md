# Provider Go-version & release automation

Three manually-dispatched workflows that operate across all Kairos provider
repos (`kairos-io/provider-*`) for a release line. `providers.json` is the
single source of truth — add a provider or a line there and every workflow
picks it up.

| Workflow | What it does |
|----------|--------------|
| **Providers - Bump Go version** (`providers-bump-go.yaml`) | Edits every Go-version reference in each provider for a line and opens a PR against that line's base branch. **Does not merge.** |
| **Providers - Notify open PRs** (`providers-notify-prs.yaml`) | Scans each provider for open PRs on the line and emails a summary (links + CI status) to the maintainers. **Does not merge.** |
| **Providers - Cut releases** (`providers-release.yaml`) | After PRs are merged: computes the next patch tag from the latest tag on each branch (e.g. `v4.8.3` → `v4.8.4`), creates the tag + GitHub Release with notes = commit diff since the last tag, and emails a summary. Defaults to **dry-run**. |

The bump logic lives in `bump-go.sh` (idempotent; safe to run locally:
`cd <provider> && /path/to/bump-go.sh 1.26.4`). It updates `go.mod`,
`Earthfile` (`ARG GOLANG_VERSION`), `Dockerfile` (`FROM golang:`), and literal
`go-version:` pins in workflows, skipping whatever a repo doesn't have.

## Required secrets

CanvOS lives in the `spectrocloud` org but the provider repos are in
`kairos-io`, so the built-in `GITHUB_TOKEN` cannot reach them.

| Secret | Purpose |
|--------|---------|
| `PROVIDER_AUTOMATION_TOKEN` | GitHub App token or fine-grained PAT with **contents:write** + **pull-requests:write** on the `kairos-io/provider-*` repos. |
| `MAIL_SERVER`, `MAIL_PORT` | SMTP host/port for notifications (e.g. `smtp.gmail.com` / `465`). |
| `MAIL_USERNAME`, `MAIL_PASSWORD` | SMTP credentials (use an app password). |

Email recipients are fixed in the workflows: `vipin@`, `santhosh@`,
`abhinav@spectrocloud.com`.

## Typical flow

1. **Bump Go** → run *Providers - Bump Go version* with `go_version=1.26.4`,
   `line=4.8` (optionally a Jira `ticket`). One PR per provider is opened.
2. **Review** → run *Providers - Notify open PRs* (or let the optional cron
   poll); maintainers review and merge the PRs from the emailed links.
3. **Release** → run *Providers - Cut releases* with `dry_run=true` to preview
   the next tags + notes (emailed), then re-run with `dry_run=false` to create
   the tags and GitHub Releases.

## Notes / future

- Reactive alternative: configure **Renovate** in each provider repo (custom
  managers for the `Earthfile` ARG and literal `go-version:`) so Go bumps open
  automatically on each Go release, without dispatching this workflow.
- Auto-merge is intentionally out of scope (chosen "notify, not merge").
