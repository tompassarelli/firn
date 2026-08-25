---
name: cloudflare-deploy-distilled
description: Authenticate, deploy, and verify Cloudflare Workers and Pages projects on this machine. Use whenever a request involves Wrangler authentication, a Cloudflare production deployment, publishing a site or Worker, checking whether a Cloudflare deploy reached its domains, or diagnosing missing Cloudflare credentials.
---

# Cloudflare deployment

Use `with-cloudflare <profile> -- <command>` for every authenticated Cloudflare
command. Never run `wrangler login`, expose a credential in any form, or fall
back to OAuth. Prefer the project profile; use `admin` only when necessary.

1. Read the repository instructions and Cloudflare configuration.
2. Prefer its production script. Otherwise run existing checks and build, then
   Wrangler through the launcher.
3. Verify the public domain and expected version or content; Wrangler success
   alone is insufficient.

For missing credentials, inspect profile and secret filenames, never contents.
Repair encrypted Firn source and activate a landed change with `firn rebuild`.
Route profile, launcher, Gjoa, and credential-source detail through
`agents path cloudflare-deploy-reference`.
