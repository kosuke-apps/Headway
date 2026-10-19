import os

/// Timings of the launch; read them with `log show --predicate 'subsystem == "dev.kosuke.headway"'`.
let launchLog = Logger(subsystem: "dev.kosuke.headway", category: "launch")

/// How fresh each new vehicle feed was when it arrived and how many requests it took (the cost of staying live); read them
/// the same way, with `category == "poll"`.
let pollLog = Logger(subsystem: "dev.kosuke.headway", category: "poll")
