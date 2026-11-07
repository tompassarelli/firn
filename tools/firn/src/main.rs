#![forbid(unsafe_code)]

mod host_idle;
mod profile;
mod system_policy;
mod unit_flags;
mod wm;

fn main() {
    match std::env::args().nth(1).as_deref() {
        Some("system-policy") => system_policy::run(),
        Some("host") => host_idle::run(),
        Some("unit-flags") => unit_flags::run(),
        Some("profile") => profile::run(),
        Some("wm") => wm::run(),
        _ => {
            eprintln!(
                "usage: firn-tools system-policy | firn-tools host idle|restart-user-manager <host> | firn-tools unit-flags --repo DIR [--north PATH] | firn-tools profile replace NAME INSTALLABLE [NIX_ARGS...] | firn-tools wm SUBCOMMAND"
            );
            std::process::exit(64);
        }
    }
}
