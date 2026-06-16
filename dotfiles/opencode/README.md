# opencode config (open-weight, BYO key)

`opencode.json` is symlinked to `~/.config/opencode/opencode.json` by the
`myConfig.modules.opencode` module (via `mkOutOfStoreSymlink`, so edits here are
live without a rebuild).

The provider is the **Hugging Face router** (`https://router.huggingface.co/v1`),
an OpenAI-compatible endpoint that fronts the open-weight model field. The API
key is read from the **`HF_TOKEN`** env var — **never hardcode it here** (repo
rule + gitleaks pre-commit hook).

## The one action left to you: set HF_TOKEN

1. Get a token at <https://huggingface.co/settings/tokens> (a "Read" token with
   Inference Providers access is enough).
2. Make it available to opencode. Two options:
   - **Quick (session):** `export HF_TOKEN=hf_xxx` in your shell before running
     `opencode`. Put it in a **git-ignored** file you source — not in this repo.
   - **Declarative (preferred, sops-nix):** add `hf-token` to `secrets/`,
     `sops.secrets."hf-token"`, render it to a file, and export it in your shell
     env. This keeps the secret encrypted in-repo. (Requires your sops key — your
     action.)

opencode also supports `opencode auth login` if you prefer its own credential
store over the env var.

## Models (swap freely — this is the whole point)

- Default is **GLM-5.1**. Change the root `"model"` to switch the default, or use
  `/models` inside opencode to switch per-session.
- **Verify each model id** on its Hugging Face page → "Inference Providers" tab.
  Repo ids and which providers serve them drift; the slugs here are starting
  points. To pin a specific provider, append it: e.g. `zai-org/GLM-5.1:novita`.
- Add a model by adding one entry under `provider.huggingface.models`.

## Re-pointing at a different provider (no lock-in)

The portability guarantee: change `baseURL` (+ the key env var) to point at
DeepInfra, Together, or your own self-hosted vLLM — nothing else changes. The
model strings stay the same shape; opencode stays identical.
