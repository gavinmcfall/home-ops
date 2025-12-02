# Bootstrap

Apply bootstrap secrets before Flux/External-Secrets are running.

## Prerequisites

1. 1Password CLI installed and signed in:
   ```bash
   op signin
   ```

2. Required 1Password entries in `kubernetes` vault:
   - `sops` with field `SOPS_PRIVATE_KEY` (age private key)
   - `1password` with fields `OP_CREDENTIALS_JSON` and `OP_CONNECT_TOKEN`

## Usage

Preview what will be applied:
```bash
task bootstrap:secrets:dry-run
```

Apply secrets:
```bash
task bootstrap:secrets
```

## What Gets Created

| Secret | Namespace | Purpose |
|--------|-----------|---------|
| `sops-age-secret` | `flux-system` | SOPS decryption key for Flux |
| `onepassword-secret` | `external-secrets` | 1Password Connect credentials |
