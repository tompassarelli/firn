---
name: vast-ai
description: >-
  Use Tom's vast.ai GPU rental account, and keep its prepaid credit from running out.
grounded: 2026-10-10
written: 2026-10-10
metadata:
  kind: playbook
---

# vast.ai

- Account: Tom's vast.ai account (`https://cloud.vast.ai`), created 2026-10-10 with $10 of prepaid credit for agent work; Tom approved one API key (billing read-only) in `nixos-config:secrets/vastai.yaml` (decrypt per docs/secrets.md); ask Tom once before topping up or changing billing.
- Use it for asset-free CPU work that already runs on GitHub runners (balance and CPU fields, suites, soaks), on CPU-only hosts.
- Billing is prepaid credit only: Tom removed the saved card on 2026-10-10, so a negative balance cannot charge a card. At $0 balance instances stop but are not destroyed, and storage charges keep accruing; a balance that stays negative ends with all data deleted permanently.
- Run every vast.ai job through `vast-job`; never rent by hand. The `vast-reaper` timer destroys any vast-job instance past its label deadline or whose supervisor died, and only reports unlabelled ones; for the `vast-launch-check` runner VM it warns once at credit <= $5.00 and at <= $2.50 deletes `FARM_RUNNER` on smashcraft and wisp, destroys the VM and removes its SSH key.
- Never let the balance reach $0: before renting, read the balance and the instance's hourly price including storage, and rent only when the balance covers the planned hours plus $2 margin.
- Destroy every instance and volume as soon as its work is copied off; a stopped instance still bills storage.
- Copy results off an instance before ending a session; never leave the only copy on vast.ai storage.
- No card is saved, so auto top-up is off; adding a card or enabling it is Tom's billing choice, so recommend it rather than doing it.
- Treat vast.ai like any rented server (Tom's call, 2026-10-10): private game files may go there when a job runs faster there; destroy the instance and volume when it ends.
- At each session end, report the balance, running instances and volumes, and confirm none is left billing.
- Rent hosts of 64 threads or fewer for Bun fields: a 256-thread EPYC 7B12 at $0.53/h ran cpuField about 10× slower than GitHub runners (load 764, ~5 matches/s; 2026-10-10), so effective cores per dollar overstates big shared hosts.
- Spend the credit on the one runner and Warcraft VM until Hetzner answers Tom, then move there as the better fit (Tom, 2026-10-10: vast works well enough to stay on if Hetzner stays silent; $34 on 10 Oct covers about 90 h at $0.352/h, and Tom checks the balance daily and tops up by hand when it drops below $10, so do not ask him to top up); rent any other instance only through `vast-job` for a critical-path result the farm cannot deliver within an hour, with the cost cap, host filter and expected runtime written in the brief and checked by the lead before launch.
- Before any vast.ai step that bills (rental, re-rental after a failed boot, large transfer), name the failure that would waste it and the check that prevents it: VM images need the full `docker.io/vastai/kvm:...` name and an explicit VM size, and a first rental that boots without SSH is destroyed at once, not retried blind.

## Warcraft VM (instance 55161577)

- Reach it with `ssh -F ~/.local/state/smashcraft/vast-launch-check/ssh_config vast` (root; work as `user`; Plasma on `:0` is not private); its desktop only through `desktop.sh` there, an SSH tunnel to VNC, never on Tom's screen. Never stop or touch its 13 `ghr-*` GitHub runner units.
- Warcraft III 3.0.0.24268 lives at `/home/user/client/install`; Battle.net (`bnet.service`, prefix `/home/user/bnet`) reaches it through a `C:\Program Files (x86)\Warcraft III` symlink, and its Agent logs "Found symlink while checking permissions" on every update.
- The 2026-10-10 install upload stopped early: 14 of the `Data/data/data.###` archives are short (10.5 GB missing), so the game says "Game data is unable to load and must be repaired" and Battle.net shows `.patch.result` 5011 ("needs repair"). Resume with `rsync -a --append-verify` per short file from `~/.local/share/wisp/lan/isolated24342-20261008/clients/lan0a` (3.1 MB/s over 13 streams to Japan, about 55 min), then sync the small files with `rsync -rlc --exclude _retail_/ --exclude 'Data/data/data.*'`; keep at most 10 parallel SSH connections, or sshd drops the rest.
- Offline LAN pool recipe, from `~/code/smashcraft/ts` with `PATH=$HOME/bin:$HOME/.bun/bin:$PATH`: `~/bin/pool-installs.sh` (data archives hard-linked, every other file copied, because the game writes its CASC indices at launch), `bun wisp lan setup --from ~/client/install --pairs 1`, then `bun wisp lan pool --pairs 1 --desktop ~/bin/vm-desktop.sh --capacity ~/bin/vm-capacity.mjs` (sources in `~/.local/state/smashcraft/vast-launch-check/remote/`; stand-ins: `vm-desktop.sh` runs one headless apt sway 1.7 per client with Xwayland and `XWAYLAND_NO_GLAMOR=1` (start it from a fresh `su - user` or `systemd-run --uid user` so the render group applies; the pool stops on SIGINT), apt `/usr/bin/grim`, a `wlrctl` that focuses through `swaymsg`, an always-admit capacity helper, a `steam-run` that just execs; account b runs in its own sway desktop with `wayvnc 127.0.0.1 5901`) and `~/bin/lan-match.sh MAP.w3x`. The map packer builds with `gcc -O2 node_modules/wisp/native/map-pack.c -lstorm -o ~/.cache/wisp/lan/map-pack`; the private LAN plugin goes to `~/.local/share/wisp-private/lan/`.
- Account b (Tompas0x#3779) is signed in on the VM only: never sign b in anywhere else (clone-b included) while the VM holds it; Battle.net allows one session per account.
- Warcraft auto-update is off on the VM. Battle.net shows "We plan to deploy patch 3.0.1 live Octo…": once 3.0.1 is live, Play may force the update, and 3.0.1 has no LAN provider. Check `curl http://us.patch.battle.net:1119/w3/versions` before pressing Play or Update.
- Battle.net's window on `:0` often draws white; read it with `~/bin/ocr.sh` (tesseract words at screen coordinates) and dismiss its "Whoops! Looks like something broke" dialog with `systemctl restart bnet`.
