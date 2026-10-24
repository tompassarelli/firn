# Crash recovery (whiterabbit — silent reboots)

whiterabbit has a history of **hard crashes that leave no trace**: the journal
for the dying boot is severed mid-line, no shutdown sequence, `/sys/fs/pstore`
empty. That signature = either an instant hardware power-cut (thermal trip / PSU)
or a GPU hard-hang that froze the CPU before anything flushed to disk. A clean
reboot always leaves `Reached target Shutdown` + `systemd-shutdown`; a crash does
not. This is the tell.

**Diagnose — classify each recent boot as clean vs crash:**

```bash
for b in -1 -2 -3 -4 -5; do
  end=$(journalctl -b $b 2>/dev/null | grep -m1 -iE "Reached target (Shutdown|Reboot|Power-Off)|systemd-shutdown")
  kern=$(journalctl -b $b -o short 2>/dev/null | grep -m1 -oE "6\.[0-9]+\.[0-9]+")
  [ -n "$end" ] && v=CLEAN || v="*** CRASH (no shutdown seq) ***"
  printf "boot %s  kernel %-9s  %s\n" "$b" "${kern:-?}" "$v"
done
journalctl -b -1 -p err            # errors in the boot that died
journalctl -b -1 | tail -40        # exact moment of death
```

**Hardware context — do NOT re-add `amdgpu.sg_display=0`.** This GPU is a Strix
Point **APU** (Radeon 890M, RADV STRIX1), not a discrete Navi 31. On an APU the
GPU runs off system RAM via GTT, so scatter-gather display is the *normal* path —
disabling it is mis-targeted (that flag was a copy-paste from an RX 7900 page-fault
fix; dropped in 7a5e18d). Crashes predate the flag (stable 9-day runs happened
*without* it), so it was never the cause. The BIOS UMA buffer is the legit
"give the iGPU dedicated VRAM" knob; `sg_display` is unrelated.

**Capture config in place** (`modules/boot/default.nix`) — the live stack turns a
silent freeze into a captured PANIC, then auto-reboots:

- **watchdog→panic** — `kernel.hardlockup_panic=1`, `kernel.panic_on_oops=1` (sysctls, applied live on switch) + `nmi_watchdog=panic`
  (kernel param, covers early boot before sysctls run). nmi_watchdog already
  *detects* hard lockups; this makes detection PANIC instead of logging into the
  void on a box that never flushes the log.
- **soft lockups log, not panic** (18 Oct 2026) — `kernel.softlockup_panic=0` with
  `kernel.softlockup_all_cpu_backtrace=1`. Three resets on 18 Oct, each 0.5–3 min after
  Tom launched Warcraft III, left empty pstore; boots after two of them printed
  `Previous system reset reason [0x00800800]: internal CPU shutdown event occurred`
  (bit 23; bit 11 is undocumented). In two, systemd user units stopped finishing
  15–20 s before the reset while the kernel still logged — the 20 s soft-lockup
  window — so softlockup_panic was rebooting the box before any trace reached disk.
  A soft lockup now prints every CPU's stack to the persistent journal and leaves
  `amdgpu.gpu_recovery` its chance; a hard lockup still panics.
- **GPU pinned to `power_dpm_force_performance_level=high`** (24 Oct 2026, framework
  module udev rule) — a fourth reset, 30 s after a Warcraft III launch, came with the
  soft-lockup capture live and left nothing: no lockup, no amdgpu line, user units
  finishing up to the last second, same `0x00800800` reason. The SoC cut power itself,
  so this tests the 819→2900 MHz GPU clock jump at game load as the trigger; Beelink
  SER9 (HX 370) owners report the same pin stops their resets. BIOS 04.02 is the
  newest on LVFS. Costs a few watts while idle; remove it if WC3 still resets with it
  live, and next suspect RAM or power delivery.
- **memtest86+ boot entry** (24 Oct 2026, `systemd-boot.memtest86.enable`) — the
  capacity helper caps one job at 16 GiB, so an in-OS memtester covers a sixth of the
  94 GB; boot it once with `systemctl reboot --boot-loader-entry=memtest86.conf`.
  memtest86+ loops until a key or reboot and keeps no log, so read Pass and Errors on
  the screen.
- `kernel.panic=20` — auto-reboot 20s after a panic so the box recovers; by then the
  capture is archived. Keeps an unattended desktop from sitting dead.
- `efi_pstore` (firmware default) — now the primary catch: freeze→panic dumps the
  backtrace to UEFI vars, archived to `/var/lib/systemd/pstore/` next boot.
- `amdgpu.gpu_recovery=1` — amdgpu resets+logs a *recoverable* GPU ring-timeout
  instead of freezing; journal dump flushes after the reset.
- journald `Storage=persistent` — `journalctl -b -1` reads the dead boot.
- **Diagnostic — remove once root cause is found.**

**Paths deliberately NOT taken** (both verified broken on this box, 2026-06-29):

- **ramoops** — this kernel runs ONE pstore backend; `efi_pstore` registers first, so
  ramoops is ignored (`registering with pstore failed … -16`). And `CONFIG_PSTORE_CONSOLE`
  is off, so without a continuous mirror ramoops only dumps on panic — redundant with
  efi_pstore. Worth it ONLY via a kernel rebuild enabling `CONFIG_PSTORE_CONSOLE` +
  `pstore.backend=ramoops` — then it's a live console mirror that catches a *no-panic*
  freeze (survives a warm reboot). Deferred until the pstore backtrace proves insufficient.
- **kdump** (`boot.crashDump`) — reserves `crashkernel=` but NixOS ships NO vmcore-save
  unit; the capture kernel drops to a shell with no auto-save and no auto-reboot, so it
  STRANDS an unattended box. Revisit only with a real save+reboot capture init.

**GPU faults have a userspace trigger (2026-06-29, via gjoa):** the Jun-27 SQC
page-fault → `gfx_0.0.0` ring-timeout was driven by many headless Firefox/WebRender
instances on amdgpu. Mitigation: those browser boots now force
software rendering (llvmpipe), so they no longer touch the GPU. That fault RECOVERED
(gpu_recovery did its job); the *fatal* silent crashes left no GPU trace, so they
remain unproven and may be a different cause — the panic stack above is to settle it.
GPU is `gfx_v11_0_0` (Strix Point APU, VCN 4.0.5); kernel 6.18.35; linux-firmware
20260519. **Root cause = a known-OPEN amdgpu CWSR regression on gfx1150** (broken
Compute Wavefront Save/Restore saturates the MES ring → SQC/UTCL2 page-fault →
ring-timeout/reset loop), present across kernel 6.18.x AND 6.19.x. **Do NOT bump
kernel/firmware to fix it** — no upstream fix exists, 6.19 still hangs + adds
reverted regressions, and newer MES microcode (0x82/0x83) is the *trigger* (older
0x80 didn't hang). Mitigation applied: `amdgpu.cwsr_enable=0`. Last-resort fallback:
pin kernel 6.17.x (pre-regression). Refs: github.com/pop-os/cosmic-comp/issues/2149,
community.frame.work/t/79221.

**After the next crash — checklist:**

```bash
ls -R /var/lib/systemd/pstore/                               # panic backtrace captured?
cat /var/lib/systemd/pstore/*/dmesg.txt 2>/dev/null          # read the backtrace
journalctl -b -1 | tail -60                                  # last moments of dead boot
journalctl -b -1 | grep -iE "ring.*timeout|GPU reset|amdgpu.*(hang|fault|reset)"
journalctl -b -1 | grep -iE "thermal|throttl|mce|hardware error|critical temp"
```

- **Panic backtrace in pstore** → software lockup; the trace names the subsystem (bet
  amdgpu/WebRender if it predates the llvmpipe fix). Fix = amdgpu/mesa lever (kernel or
  firmware bump, `amdgpu.lockup_timeout`, RADV/mesa, IOMMU), NOT sg_display.
- **GPU ring-timeout / reset logged, no panic** → recoverable amdgpu hang (gpu_recovery).
- **Still zero trace** (no panic, no pstore) → NMI couldn't fire: true SoC freeze or
  instant hardware power-cut. THEN do the `CONFIG_PSTORE_CONSOLE` rebuild or netconsole,
  and check `sensors` under load / fans / BIOS thermal limits / PSU.

## Battery drain and the unresumable hibernate (25 Oct 2026)

**What happened.** UPower's history (`/var/lib/upower/history-*-FRANGWA-60-02CB.dat`)
shows the battery switching from charging to discharging at 00:39:41 local time at 56%, with
no kernel or logind line naming why, then losing about 1.3% a minute at 25–40 W of agent
load (native Warcraft clients were running). At 2% UPower's `CriticalPowerAction=HybridSleep`
fired: logind logged `The system will hybrid sleep now!` at 01:36:04, the lid-drain hook
spent its 5 s ssh timeout (`rc=124`), and the last line of the boot is
`PM: hibernation: hibernation entry` at 01:36:10. The next boot's kernel started at
01:36:38 with the AC adapter online.

**Why the image was not resumable: the write never finished.**

- The next boot's kernel said `PM: Image not found (code -22)`. `swsusp_check` returns
  `-EINVAL` when the swap header at the resume offset does not carry the hibernation
  signature, and the kernel writes that signature last, in `swap_writer_finish`, only after
  every image page is on disk.
- The resume offset is right. `btrfs inspect-internal map-swapfile -r /swap/swapfile`
  prints `347227782`, the same value as `resume_offset=` on the kernel command line, and
  the 4 KiB page at that offset on `/dev/mapper/cryptroot` ends in `SWAPSPACE2`, a plain
  swap header. A finished image would have left `S1SUSPEND` there, and `swapon` of
  `/swap/swapfile` succeeded at 01:36:53.
- `Reported hibernation image: … offset=347227782` from systemd-hibernate-resume is not
  evidence of an image. systemd-sleep writes the `HibernateLocation` EFI variable before
  the kernel starts writing, so it is present whether or not the write completed.
- No earlier boot in the journal (back to 6 Oct) has a `hibernation entry`, so this was the
  first hibernate on this install and nothing shows one ever completing here.

So the battery ran out during image creation or the write, about 20 s in. The 2% action
level left about 1.1 Wh (2% of the 56.4 Wh full charge), and at the bottom of the gauge,
under load, the remaining energy is less than the percentage claims.

**How long a hibernate write takes here.** The image is capped by `/sys/power/image_size`
(40 325 586 944 bytes, the kernel's default of 2/5 of RAM); the kernel reclaims down to
that size before writing. A 4 GiB direct write to the btrfs root through dm-crypt
measured 252 MB/s (`dd bs=16M count=256 oflag=direct conv=fsync`). A worst-case image then
takes about 160 s to write uncompressed, less with the default `lzo` hibernate
compressor, plus reclaim and amdgpu VRAM eviction. At 25–30 W that is 1.1–1.3 Wh, about
2% of the battery, the whole 2% that was left.

**Fix (in this repository).** `modules/upower` sets `PercentageLow=20`,
`PercentageCritical=12` and `PercentageAction=8`: hybrid sleep now starts with about
4.5 Wh left, roughly three times the worst-case write, which covers both the gauge error
near empty and the suspend that follows the write. `resume_offset` and `image_size` need
no change. Earlier warning comes from north: `laptop-auto` drains agent placement off the
laptop (`laptop` state `draining`, reason `battery`) once the battery is discharging
below 30%, sends one critical desktop notification for that discharge, and reopens
placement to the window when AC returns.

**Measured on the new levels (25 Oct 2026, 02:05).** AC dropped again at 01:58 while
charging at 15%, the same unexplained source drop as at 00:39. At 8% logind started a
hybrid sleep, and this time it completed. The kernel preallocated 40 GB (the
`image_size` cap) in 12.1 s, wrote 37.4 GB in 38.8 s (965 MB/s; 12.7 GB after `lzo`),
wrote the signature (`PM: S|`) and entered s2idle 102 s after `hibernation entry`. That
included the 6 s lid-drain timeout and freezing. Every session survived. The real write
is about four times faster than the `dd` estimate above, so the 8% action level leaves a
wide margin. The source drops themselves (charging, then discharging with no kernel or
logind line) still need a look at the charger and cable.
