---
name: cloudflare-deploy
description: >-
  Authenticate, deploy, and verify Cloudflare Workers or Pages through this machine's approved credential launcher.
grounded: 2026-10-06
written: 2026-10-06
---

# Cloudflare deployment

Run authenticated commands through `with-cloudflare <profile> -- <command>`.
Prefer the project's profile; use `admin` only for a required capability.
Never expose credentials, invoke `wrangler login`, or substitute OAuth.

Use the repository's production command when present. Otherwise run its
required checks and build, then Wrangler through the launcher. Verify the
public domain and expected content or version before declaring deployment done.

For missing access, inspect profile declarations and secret filenames, not
contents. Repair encrypted Firn source and activate its landed change through
the Firn workflow. For profiles and credential sources, use
`references/notes.md`.
