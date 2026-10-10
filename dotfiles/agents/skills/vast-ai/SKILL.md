---
name: vast-ai
description: >-
  Use Tom's vast.ai GPU rental account, and keep its prepaid credit from running out.
grounded: 2026-10-10
written: 2026-10-10
---

# vast.ai

- Account: Tom's vast.ai account (`https://cloud.vast.ai`), created 2026-10-10 with $10 of prepaid credit for agent work; Tom approved one API key (billing read-only) in `nixos-config:secrets/vastai.yaml` (decrypt per docs/secrets.md); ask Tom once before topping up or changing billing.
- Use it for asset-free CPU work that already runs on GitHub runners (balance and CPU fields, suites, soaks), on CPU-only hosts.
- Billing is prepaid credit only: Tom removed the saved card on 2026-10-10, so a negative balance cannot charge a card. At $0 balance instances stop but are not destroyed, and storage charges keep accruing; a balance that stays negative ends with all data deleted permanently.
- Run every vast.ai job through `vast-job`; never rent by hand. The `vast-reaper` timer destroys any vast-job instance past its label deadline or whose supervisor died, and only reports unlabelled ones such as `vast-launch-check`.
- Never let the balance reach $0: before renting, read the balance and the instance's hourly price including storage, and rent only when the balance covers the planned hours plus $2 margin.
- Destroy every instance and volume as soon as its work is copied off; a stopped instance still bills storage.
- Copy results off an instance before ending a session; never leave the only copy on vast.ai storage.
- No card is saved, so auto top-up is off; adding a card or enabling it is Tom's billing choice, so recommend it rather than doing it.
- Treat vast.ai like any rented server (Tom's call, 2026-10-10): private game files may go there when a job runs faster there; destroy the instance and volume when it ends.
- At each session end, report the balance, running instances and volumes, and confirm none is left billing.
