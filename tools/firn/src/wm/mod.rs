mod facts;
mod ledger;
mod marks;
mod niri;
mod rofi;

const USAGE: &str = "usage: firn-tools wm mark|unmark|marks|jump|query|mark-rofi|jump-rofi|facts-daemon [ARGS]";

pub struct Failure {
    code: i32,
    message: String,
}

impl Failure {
    fn new(code: i32, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
        }
    }

    fn usage(message: &str) -> Self {
        Self::new(2, message)
    }
}

impl From<String> for Failure {
    fn from(message: String) -> Self {
        Self::new(1, message)
    }
}

pub fn run() {
    let args: Vec<String> = std::env::args().skip(2).collect();
    let rest = args.get(1..).unwrap_or_default();
    let outcome = match args.first().map(String::as_str) {
        Some("mark") => marks::mark(rest),
        Some("unmark") => marks::unmark(rest),
        Some("marks") => marks::list(),
        Some("jump") => marks::jump(rest),
        Some("query") => facts::query(rest),
        Some("mark-rofi") => rofi::mark(),
        Some("jump-rofi") => rofi::jump(),
        Some("facts-daemon") => facts::daemon(),
        _ => Err(Failure::new(64, USAGE)),
    };
    if let Err(failure) = outcome {
        eprintln!("{}", failure.message);
        std::process::exit(failure.code);
    }
}
