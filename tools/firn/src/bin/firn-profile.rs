#![forbid(unsafe_code)]

#[path = "../profile.rs"]
mod profile;

fn main() {
    profile::run();
}
