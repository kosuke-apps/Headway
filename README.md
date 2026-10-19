# Headway

A fast, live bus map for Madison, WI (Metro Transit): every route and stop on an offline map, buses moving in real
time, and the next arrivals at any stop. English UI with a Japanese localization.

Headway is an independent project. It is not made, endorsed or supported by the City of Madison or Metro Transit; it uses
the data the city publishes (see Data below), and bus times can differ from what the buses do.

## Features

- **Offline map.** The Madison-area basemap is stored in the app; only the live data needs a connection: the bus
  positions (7 KB per update, about 2 MB an hour) and, while a stop or bus is open, the arrival predictions (160 KB, at
  most once a minute). Settings > Live buses > "Save mobile data" (and the icon beside it) lets you choose how often
  predictions are fetched on Wi-Fi and on mobile data, keeps the 7 MB timetable for Wi-Fi, and shows a data meter. Live bus
  positions are never slowed by a data setting.
- **Everything visible at once.** All routes, all stops (names appear when zoomed in) and all buses, with the route
  name on each bus.
- **Live arrivals.** Tap a stop to see the next buses, live where a bus is reporting ("4 min · 1 min late") and from
  the timetable otherwise, plus the full timetable for any of the next 7 days.
- **Service alerts.** Detours and other alerts that affect a stop's routes appear at the top of its sheet. Routes with
  an alert in force are drawn dashed, and a bus far from its usual line is ringed in orange.
- **Modes** (hamburger menu, top left): the Map; **Service info** (alerts, delays per route, cancelled trips, trips
  that should be running but report no position, and the next buses at your favourite stops); and **Plan a trip**.
- **Trip planner.** From your location, a stop, a place found by name (Apple Maps, needs a connection) or a pin you
  long-press on the map, to anywhere. It finds journeys with walking and transfers, takes the live delay of reporting
  buses into account, shows them step by step and draws them on the map. Leave now, depart at, or **arrive by**; earlier
  and later buses; sort by departure, arrival, transfers or walking; badges for the fastest, fewest-transfer and
  least-walking journeys. Up to three **stops on the way**, each with a stay time. **Saved places** (Home, Work, others), **saved trips** (one tap to plan again), recent trips,
  walking speed, longest walk, most transfers, time to change buses, wheelchair-accessible only, a reminder before you
  have to leave, and sharing a journey as text.
- **How punctual, and how live.** The live line reports the age of the bus positions (they are about 25 s old; the city's
  feed is rebuilt every 30 s). Buses are moved along their route between reports. Stop sheets show, for the time of week,
  the share of buses that were early, on time or late at that stop, and live arrivals carry the range the bus has come in
  on 9 of 10 past occasions. These come from recordings the project makes itself (see `docs/data-sources.md`).
- **Follow a bus.** Tap a bus to see its next stops with predicted times.
- **Directions.** Many Madison streets are one-way, so the two directions of a route often differ. Routes are listed by
  direction ("Westbound to ..."), the favourite-stop cards say where their buses go, and arrows along a route show which
  way its buses run.
- **Overlapping routes.** Routes that share a street are drawn side by side in lanes on one shared centre line, like a
  transit diagram, with one line per route where both directions use the same street; tapping lines of several routes
  asks which one you meant.
- **Which way a bus goes.** Each bus shows its route and pattern ("D2"), a small letter for the way its trip runs
  ("E", "W", "N", "S") and a white or black ring (white for east- and northbound, black for west- and southbound).
- **How the buses of a route are doing.** The routes list, the route chooser and the chip over the map count the buses of a
  route (of each direction, of each destination) and colour them: red late (over 5 minutes), green on time, blue early
  (over 2 minutes). A route with an alert has a triangle. Tapping the bar over the map ("Live · 126 buses") opens the
  same for the whole network, with a refresh button.
- **The history behind a percentage.** Touching a punctuality bar ("Usually at this stop") opens a screen with hour-by-hour
  charts for weekdays, Saturdays or Sundays, for the stop or the whole route: the share of early, on-time and late arrivals,
  and how far from the timetable most buses were. Touch a bar for the numbers of that hour.
- **Buses that are not on a trip** (out of service, or waiting at a terminal) are pale with an orange ring and a "!", so
  that nobody boards one by mistake; when the city already lists the trip a bus will run next, the marker shows that route
  and its departure time, and the bus's sheet says where it starts.
- **First and last stop.** A route looked at on its own rings its first stop in purple and its last in black (white on
  the dark map); with several destinations in a direction, each end says which pattern it belongs to ("D1", "D2").
- **Which destination.** A route with several destinations in one direction (D1 to Junction, D2 to Epic Campus, ...) can be
  narrowed to one of them from the chip over the map: its line, stops and buses are shown alone.
- **Back to the list.** "Show on map" from an alert, a delay or the routes list leaves a back button on the chip over the
  map, so you return to where you came from.
- **Delays without losing the timetable.** A live bus shows how many minutes late or early it is, with the timetable's own
  time next to it (it is never replaced); the full timetable marks live buses with +3 or −2 beside their minute.
- **Which side of the street.** Stops of the same name on either side of a street are told apart: the stop sheet, search,
  planner steps and timetable say "Southbound" and so on, and an arrow beside each stop on the map shows the way. Each route and direction says how many buses are running, or why
  there are none (not running today, between trips), with the next trip.
- **Focus.** Tap a route, or one direction of it, to see only that on the map (other routes are hidden or faded, as you
  choose in Settings); an alert's **Show on map** link does the same and rings the stops its text names; the delay rows
  of Service info show the late or early buses on the map. Hide routes you never use.
- **Notifications.** Watch routes (swipe a route) and be told when one is late, early or has an alert. Local
  notifications only: Headway checks while it is open and, when iOS allows, in the background, so they are best effort.
- **Search** by stop name or sign number; favourites, recents and nearby stops.
- **Language.** English or Japanese, chosen in Settings > Behavior > Language (or "System default", which follows iOS). The change
  applies at once, without restarting. Dates, numbers and distances keep following the phone's region, and the map's labels
  stay in English (the city's stop and destination names are English).
- **Customization.** Light, dark or system theme; three colour palettes (Metro Transit, colour-blind-safe,
  quiet); line thickness; bus marker size; when to show stops; update interval (5-30 s); smooth bus movement;
  12/24-hour clock; minutes or clock times; delay details; haptics.
- Honest about data: a clock icon marks times that come only from the timetable.

Status: working prototype. It runs on an iPhone 12 Pro (free Personal Team signing) and in the iOS Simulator.

## Permissions

- **Location (While Using the App)**: to show where you are on the map, find nearby stops and plan from where you are.
  It stays on the phone. Everything else works without it.
- **Notifications** (optional): to tell you that a watched route is late, early or has an alert, and when to leave.
  They are local; there is no push server.
- **Background refresh** (optional): lets iOS wake the app now and then to check the routes you watch.

The only network requests are to the City of Madison's public feeds and, when you search for a place by name, to Apple
Maps. See [PRIVACY.md](PRIVACY.md).

## Installing

Headway is not on the App Store. You put it on your own iPhone (iOS 17 or later), signed with your own Apple ID,
because Apple only runs signed apps. There are two ways.

**Build it yourself (the main way, and how the author installs it).** You need a Mac with Xcode and the tools under
Getting started below. Connect the iPhone, then:

```bash
tools/fetch_basemap.sh && tools/fetch_timetable.sh && tools/build_punctuality.sh   # data the app bundles
cp Config/Local.xcconfig.example Config/Local.xcconfig                             # then put your Apple Team ID in it
tools/run_on_device.sh                                                             # builds, installs and starts it
```

`docs/run-on-iphone.md` has the one-time steps (Developer Mode on the phone, trusting your Apple ID the first time). With
a free Apple ID the app has to be installed again every 7 days.

**Or take a release build (no build needed, but a second tool is).** Each
[release](https://github.com/kosuke-apps/Headway/releases) has an unsigned `Headway-<version>-unsigned.ipa` and its
checksum. Check the download with `shasum -a 256 -c Headway-<version>-unsigned.ipa.sha256`, then install the `.ipa` with a
sideloading tool that signs with your own Apple ID, such as [AltStore](https://altstore.io) or
[Sideloadly](https://sideloadly.io). The file is deliberately unsigned, so it carries no signature of mine. With a free
Apple ID, such tools are widely reported to install an app that stops opening after 7 days (it has to be signed again) and
to allow three apps at a time; that comes from the tools' own pages and community reports, not from Apple's documentation,
so check the tool's page for the current limits. The author has not tried this route; it is checked only as far as the
file's contents (unsigned, licence texts present, no personal data).

## Getting started

Needs Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen), [pmtiles](https://github.com/protomaps/go-pmtiles),
and Node (for the map style). With Homebrew: `brew install xcodegen pmtiles node`.

```bash
tools/fetch_basemap.sh      # map tiles (18 MB) and label glyphs
tools/fetch_timetable.sh    # timetable bundled for the first launch (7 MB)
tools/build_punctuality.sh  # punctuality statistics from recordings (an empty table if there are none)
xcodegen generate           # creates Headway.xcodeproj
open Headway.xcodeproj      # run on a simulator or your iPhone
```

To run on your own iPhone, see Installing above and `docs/run-on-iphone.md`.

## Data

| What | Source |
|---|---|
| Timetable (GTFS) and live positions, predictions, alerts (GTFS-Realtime) | City of Madison, WI, Metro Transit. See `docs/data-sources.md` for URLs and terms |
| Map | © OpenStreetMap contributors, via a Protomaps build |

## Architecture

- `Sources/HeadwayCore`: GTFS and GTFS-Realtime parsing, arrivals logic. No UI; tested with `swift test`.
- `App/`: SwiftUI app with MapLibre Native. See `AGENTS.md` for the file-by-file map.
- `collector/`: a Cloudflare Worker (free plan) that records the city's feeds around the clock; `tools/pull_feeds.py`
  brings the recordings to the Mac. See `collector/README.md`.
- `tools/`: feed recorder, analysis, map and icon generation.
- `docs/`: data sources and findings.

## Quality checks

```bash
swift test                                                       # data layer (147 tests)
xcodebuild test -project Headway.xcodeproj -scheme Headway \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' CODE_SIGNING_ALLOWED=NO   # app tests (83)
(cd collector && npm test)                                       # collector, in Cloudflare's runtime (9 tests)
```

## Licence

Headway is released under the MIT licence: Copyright (c) 2026 Kosuke Satake (see [LICENSE](LICENSE)). The libraries, fonts
and map styles it contains, and the data it uses, have their own terms: see [THIRD_PARTY.md](THIRD_PARTY.md), and
Settings > Licences inside the app. The city's data terms are summarised in `docs/data-sources.md`.

This project accepts issues, not code contributions.

## About the making of this app

This app was built with the help of Claude (Anthropic) through Claude Code; design, review and testing are by Kosuke Satake. Anthropic does not endorse this app.

