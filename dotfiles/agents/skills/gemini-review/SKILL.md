---
name: gemini-review
description: >-
  Get an extra adversarial review of a public diff or design from Gemini's strongest Pro model through the Antigravity CLI (`agy`) on Tom's Google AI plan.
grounded: 2026-10-10
written: 2026-10-10
metadata:
  kind: playbook
---

# Gemini review

Gemini is an extra reviewer from another model family; `workers` sets
when it runs and how much its findings weigh. Google retired Gemini CLI for
personal accounts on 2026-06-18; the Antigravity CLI `agy` replaces it.

## Public code only

Antigravity's terms let Google use, and its staff review, prompts and
outputs to improve its models unless Tom turned that off in Antigravity's
settings. Send it only public repositories (smashcraft, wisp and other
public repos). Never send extracted game files, anything under
`~/code/clients/`, secrets, credentials or private transcripts.

## Call it

- Headless run: `agy -p "<lens + task>
$(git diff origin/main...)" --model <slug> --sandbox`; keep the prompt
  under 100 KB (one argument), otherwise review per file.
- Use the strongest Pro slug at its highest effort for every review
  (`gemini-3.1-pro-high` on 2026-10-10; Tom's plan includes Pro). Check
  `agy models` for a newer Pro before a design review.
- Never pass `--dangerously-skip-permissions`; without it, tools that need
  approval are soft-denied, so it cannot edit or run commands.
- Ask for findings with a failing scenario, test or measurement each, and
  for `Accepted flaws: N`; relay findings, never let it edit.
- A non-zero exit means auth, quota or model failure; skip Gemini rather
  than retrying.

## Quota and auth

- Google account sign-in on Tom's $20/month Google AI plan only; never an
  API key (`GEMINI_API_KEY`) or API billing. Tom signs in once by running `agy` in a terminal; the token
  lives in the GNOME keyring.
- The plan's quota is unpublished; `/usage` shows what is
  left. One review prompt costs several requests when it reads files.
