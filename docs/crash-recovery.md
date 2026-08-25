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

**Capture config in place** (`modules/boot/default.bnix`) — the live stack turns a
silent freeze into a captured PANIC, then auto-reboots:

- **watchdog→panic** — `kernel.hardlockup_panic=1`, `kernel.softlockup_panic=1`,
  `kernel.panic_on_oops=1` (sysctls, applied live on switch) + `nmi_watchdog=panic`
  (kernel param, covers early boot before sysctls run). nmi_watchdog already
  *detects* hard lockups; this makes detection PANIC instead of logging into the
  void on a box that never flushes the log.
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
