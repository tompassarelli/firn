---
name: gemini-review
description: >-
  Get a cheap extra adversarial review of a public diff or design from Gemini CLI on the free Google-account tier.
grounded: 2026-10-10
written: 2026-10-10
---

# Gemini review

Gemini is a cheap extra reviewer from another model family; `workers` sets
when it runs and how much its findings weigh.

## Public code only

The free tier (Gemini Code Assist for individuals, Google account sign-in)
may use prompts and code to improve Google's models unless Tom opted out
with `/privacy`. Send it only public repositories (smashcraft, wisp and
other public repos). Never send extracted game files, anything under
`~/code/clients/`, secrets, credentials or private transcripts.

## Call it

- Pipe the material on stdin; `-p` forces headless mode and is appended
  to stdin: `git diff origin/main... | gemini -p "<lens + task>" --approval-mode plan -o text`.
- Use `--approval-mode plan` so it reads and never edits or runs tools.
- Use `-m pro` for designs and `-m flash` for routine diffs.
- Ask for findings with a failing scenario, test or measurement each, and
  for `Accepted flaws: N`; relay findings, never let it edit.
- Exit 1 means API or quota failure; skip Gemini rather than retrying.

## Quota and auth

- Google account sign-in only; never an API key or billing. Tom signs in
  once with `gemini` in a terminal; credentials stay in `~/.gemini/`.
- Free quota: 1,000 model requests per user per day plus a per-minute
  limit; one review prompt is several requests when it reads files.
