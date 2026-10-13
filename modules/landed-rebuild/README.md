`firn rebuild --landed SHA` requests the current public Firn main tip through
a root-owned Unix socket service. The service fetches the fixed public origin,
authenticates the Linux socket peer, and builds root-owned committed snapshots.
The installed private overlay must bind `myConfig.modules.landed-rebuild.systemFlake`
to its immutable `self.outPath`; requests refuse activation when it is absent.

The privileged runtime is a generated bundle of Firn's existing rebuild core.
Regenerate it with `bash modules/landed-rebuild/build-runtime.sh` whenever its
host adapter or the imported rebuild sources change. Root execution uses
system/store programs. Validation and the existing user environment helper run
as the configured user with `no_new_privs` and a fixed environment.

The Beagle collection runtime bundled into `runtime.mjs` comes from
`https://github.com/tompassarelli/beagle`, revision
`bfe06d21f4bdb82f7017770fd73863f63e3feeef`. Its license is MIT OR Apache-2.0;
this bundle uses MIT with the notice preserved in `LICENSE-BEAGLE`.

The service stays running during configuration switches so it can deliver the
request result. Changes to its installed service/runtime take effect after a
service restart or reboot.
