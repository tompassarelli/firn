`firn rebuild --landed SHA` requests the current public Firn main tip through
a root-owned Unix socket service. The service fetches the fixed public origin,
authenticates the Linux socket peer, and builds root-owned committed snapshots.
With `systemFlake` set, each request also fetches that repository's main from
its origin as root, with a one-hour contents-read GitHub App token minted per
request when the origin is private, and builds it around the Firn snapshot.

The privileged runtime is a generated bundle of Firn's existing rebuild core.
Regenerate it with `bash modules/landed-rebuild/build-runtime.sh` whenever its
host adapter or the imported rebuild sources change. Root execution uses
system/store programs. Validation and the existing user environment helper run
as the configured user with `no_new_privs` and a fixed environment.

The bundle is built from the TypeScript rebuild family in `native/` with Bun.
The ported native JSON codec retains its original MIT OR Apache-2.0 license;
the MIT notice is preserved in `LICENSE-BEAGLE`.

The service stays running during configuration switches so it can deliver the
request result, then exits; systemd starts the installed unit afresh for the
next request, so a change to the service takes effect from that request on.
