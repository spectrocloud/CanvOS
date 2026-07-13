# Release helper scripts

## `encrypt-creds.sh`

Encrypts release credentials (RHSM user/pass, Ubuntu Pro token) so they can
be pasted into the **Build Kairos Init Base Images** workflow without ever
appearing in cleartext anywhere.

### One-time setup

Install `age` locally:

```bash
# macOS
brew install age

# Ubuntu / Debian
sudo apt install age

# Anything else — grab a binary release
https://github.com/FiloSottile/age/releases
```

### Every time you dispatch the workflow

From a clean checkout of this repo:

```bash
./scripts/encrypt-creds.sh
```

You'll be prompted three times (silently). Leave a prompt blank to skip
that credential — the workflow will then skip the corresponding image
family.

The script prints three ciphertext blocks. Copy each block into the
matching field of the workflow_dispatch form on GitHub:

| Prompt asked | Workflow input to paste into |
|---|---|
| RHSM username | `rhel_subscription_username_encrypted` |
| RHSM password | `rhel_subscription_password_encrypted` |
| Ubuntu Pro token | `ubuntu_pro_token_encrypted` |

### Why encryption

The workflow_dispatch UI shows raw string inputs in cleartext in the
"Inputs" panel, in log env dumps, and in run-summary APIs. Ciphertexts are
useless without the private key — which lives only as the repo secret
`WORKFLOW_DECRYPT_KEY` and never as a workflow input. See
`.github/scripts/decrypt-creds.sh` for the workflow-side decrypt logic.

### Threat model

**Protected:**
- Cleartext credentials in Actions log stream (only ciphertext appears)
- Cleartext in the dispatch Inputs panel (only ciphertext appears)
- Log retention exposing old creds (ciphertext + no key = useless)
- Screenshots of the dispatch form or run URL (ciphertext safe to share)

**Not protected:**
- A repo-write-access user modifying the workflow to echo decrypted values.
  Mitigate with branch protection on the workflow file and required
  reviewers on the release environment.
- Compromise of your local machine while running `encrypt-creds.sh` — the
  plaintext exists in your shell during the run.
- Compromise of the private key (repo secret). Rotation procedure below.

### Rotation

If the private key is compromised or on scheduled rotation:

1. Generate a new keypair:
   ```bash
   age-keygen -o new-workflow-decrypt.key
   ```
2. Replace `team.age.pub` in the repo with the new public key.
3. Update the `WORKFLOW_DECRYPT_KEY` repo secret with the new private key.
4. Old ciphertexts stop working — users re-encrypt using the new
   `team.age.pub` on their next dispatch.

A team member leaving is **not** a rotation trigger — they never held the
private key.
