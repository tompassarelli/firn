#![forbid(unsafe_code)]

mod host_idle;
mod system_policy;

fn main() {
    match std::env::args().nth(1).as_deref() {
        Some("system-policy") => system_policy::run(),
        Some("host") => host_idle::run(),
        _ => {
            eprintln!(
                "usage: firn-tools system-policy | firn-tools host idle|restart-user-manager <host>"
            );
            std::process::exit(64);
        }
    }
}
