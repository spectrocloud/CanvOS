---
name: audit-backports
description: Audit merged main PRs labeled backport-<release> and report which never landed on the rc/release branch. Covers CanvOS together with stylus, crony and eclipse. Use when checking backport coverage for a release or preparing a release cut.
---

# Audit backports

A fix merged to `main` reaches the release line only if its automated backport
lands. The audit runs across stylus and every repository it consumes for a
release — `CanvOS`, `crony`, `eclipse`, `agent-mode`, and the `go.mod`
dependencies — so a CanvOS backport is not judged in isolation from the others.

The canonical script and workflow live in the stylus repository:

- `spectrocloud/stylus` → `hack/release/audit_backports.py`
- `spectrocloud/stylus` → `.github/workflows/backport-audit.yaml`
- `spectrocloud/stylus` → `.github/workflows/spadex-release.yml` (preflight)

## Run it from any checkout

```bash
tmp="$(mktemp -d)"
gh api repos/spectrocloud/stylus/contents/hack/release/audit_backports.py \
  --jq .content | base64 -d > "$tmp/audit_backports.py"
python3 "$tmp/audit_backports.py" --target rc-4.10
```

Formats: `--format markdown` (default), `text`, `slack`. Add
`--fail-on-missing` for a non-zero exit. Requires `gh` with read access to all
four repositories.

## Buckets

| Bucket | Meaning |
|--------|---------|
| Landed | Backport PR merged, or the source commit is already in the target |
| Missing | Labeled, but no `backport/<target>/pr-<n>` branch exists |
| Failed | Backport PR closed unmerged |
| Pending | Backport PR open |
| Not triggered | `backport-<target>` set without `auto-backport` |

CanvOS uses `backport-rc-<major>.<minor>` labels and
`backport/rc-<major>.<minor>/pr-<n>` branches. Dependencies with no `rc-*` branch
backport straight to `release-<major>.<minor>`; `--target rc-4.10` covers both.

## Full details

See `.claude/skills/audit-backports/SKILL.md` in `spectrocloud/stylus`.
