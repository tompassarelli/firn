#![forbid(unsafe_code)]

mod host_idle;
mod system_policy;
mod unit_flags;

fn main() {
    match std::env::args().nth(1).as_deref() {
        Some("system-policy") => system_policy::run(),
        Some("host") => host_idle::run(),
        Some("unit-flags") => unit_flags::run(),
        _ => {
            eprintln!(
                "usage: firn-tools system-policy | firn-tools host idle|restart-user-manager <host> | firn-tools unit-flags --repo DIR [--north PATH]"
            );
            std::process::exit(64);
        }
    }
}
