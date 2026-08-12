---
name: cloudflare-deploy
description: Authenticate, deploy, and verify Cloudflare Workers and Pages projects on this machine. Use whenever a request involves Wrangler authentication, a Cloudflare production deployment, publishing a site or Worker, checking whether a Cloudflare deploy reached its domains, or diagnosing missing Cloudflare credentials.
---

# Cloudflare deployment

Use the machine credential launcher instead of interactive authentication:

```bash
with-cloudflare <profile> -- <command>
```

Never run `wrangler login` on this machine. Never read, print, copy, or place a
credential in a command argument, repository file, log, or chat. The launcher
reads SOPS-projected files from `/run/secrets`, clears inherited Cloudflare auth
variables, and exports credentials only to the child process. It prefers a
profile-scoped API token and uses the legacy global key only as a fallback.

Available profiles:

- `gjoa`: Gjoa website account and production Worker.
- `admin`: cross-account administration. Use only when a project-specific
  profile cannot perform the requested operation.

For a repository deployment:

1. Read its `AGENTS.md` and Cloudflare configuration.
2. Use its production deployment script when present; that script owns the build,
   deployment, and application-specific live checks.
3. Otherwise run the repository's existing checks and build, then invoke
   Wrangler through `with-cloudflare`.
4. Verify the public domain and the application version or content after the
   deploy. Wrangler success alone is not completion.

For Gjoa, run this from the website repository after the intended commit is on
`main`:

```bash
~/code/gjoa-website/main/scripts/deploy-production
```

If `with-cloudflare` reports a missing credential, inspect the declared profile
and `/run/secrets` filenames without printing file contents. Do not fall back to
OAuth. The credential source is the encrypted Cloudflare SOPS file in the Firn
repository at `nixos-config:secrets/cloudflare.yaml`; activate a landed
configuration change with `firn rebuild`.
