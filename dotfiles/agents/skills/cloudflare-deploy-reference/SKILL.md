---
name: cloudflare-deploy-reference
description: >-
  Profile, launcher, repository-command, Gjoa, and credential-source reference
  for cloudflare-deploy-distilled. Load only when that skill routes here through
  `agents path cloudflare-deploy-reference`; this is not the trigger or minimum
  Cloudflare deployment workflow.
---

# Cloudflare deployment reference

The distilled skill owns the credential safeguards and deployment workflow.

## Credential launcher

The command shape is:

```bash
with-cloudflare <profile> -- <command>
```

The launcher reads SOPS-projected files from `/run/secrets`, clears inherited
Cloudflare authentication variables, and exports credentials only to its child
process. It prefers a profile-scoped API token and uses the legacy global key
only as a fallback.

Available profiles:

- `gjoa`: Gjoa website account and production Worker.
- `admin`: cross-account administration when a project-specific profile lacks
  the requested capability.

## Repository-owned deployment

A repository production script is the authority for its build, deploy, and
application-specific live checks. In the Gjoa website repository, after the
intended commit is on `main`, the command is:

```bash
~/code/gjoa-website/main/scripts/deploy-production
```

Without such a script, the repository's existing checks and build precede a
Wrangler command launched through the selected profile. The live observation
should name both the public domain and the expected version or content.

## Missing credential detail

The credential source is the encrypted Firn file at
`nixos-config:secrets/cloudflare.yaml`. Diagnose a missing profile through its
declaration and the filenames projected under `/run/secrets`, without opening
those files. A source change is activated through the Firn workflow after it
lands.
