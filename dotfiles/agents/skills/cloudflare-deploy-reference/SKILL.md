---
name: cloudflare-deploy-reference
description: >-
  Full Cloudflare notes for credential profiles, repository deploy authority, and missing-secret diagnosis.
---

# Cloudflare deployment: full notes

## Boundaries and rationale

The task authorizes its deployment, not unrelated account administration.
A repository production script owns build/deploy/live checks; the credential
launcher supplies only the selected account capability. Keep these authorities
separate so switching accounts cannot silently switch the deployment target.

Existing credentials may be consumed without exposing them. Never print token
values or dump authentication environments to diagnose access.

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

## Evidence and alternatives

A successful Wrangler exit establishes command success, not necessarily the
expected public content. Check the named domain and version/content through the
repository's existing live check. If a profile lacks capability, identify the
exact missing permission before choosing a broader account. Do not ask for a
new sign-in while a valid existing profile already supports the task.
