#![forbid(unsafe_code)]

mod system_policy;

fn main() {
    match std::env::args().nth(1).as_deref() {
        Some("system-policy") => system_policy::run(),
        _ => {
            eprintln!("usage: firn-tools system-policy");
            std::process::exit(64);
        }
    }
}
