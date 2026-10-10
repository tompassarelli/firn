---
name: gemini-review
description: >-
  Get a cheap extra adversarial review of a public diff or design from Gemini through the Antigravity CLI (`agy`) on a free Google-account sign-in.
grounded: 2026-10-10
written: 2026-10-10
metadata:
  kind: playbook
---

# Gemini review

Gemini is a cheap extra reviewer from another model family; `workers` sets
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
- List model slugs with `agy models`; use a Pro slug for designs and a
  Flash slug for routine diffs.
- Never pass `--dangerously-skip-permissions`; without it, tools that need
  approval are soft-denied, so it cannot edit or run commands.
- Ask for findings with a failing scenario, test or measurement each, and
  for `Accepted flaws: N`; relay findings, never let it edit.
- A non-zero exit means auth, quota or model failure; skip Gemini rather
  than retrying.

## Quota and auth

- Google account sign-in only; never an API key (`GEMINI_API_KEY`) or
  billing. Tom signs in once by running `agy` in a terminal; the token
  lives in the GNOME keyring.
- Free quota is unpublished and refreshes weekly; `/usage` shows what is
  left. One review prompt costs several requests when it reads files.
