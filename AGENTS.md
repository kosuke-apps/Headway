# Headway

An iPhone app that shows Madison, WI buses live on an offline map, with every route, stop and timetable at a glance.
The author's general workspace rules (outside this repository) apply too; this file adds what is specific to this project.

## Product

- Purpose: replace the habit of opening Google Maps as a timetable. Existing apps are slow, show timetables as plain
  lists, do not show all stops on the map, and need a connection for map tiles.
- Intended users: Madison bus riders, first the author. Later other cities (GTFS is a standard).
- Core user journey: open the app, see the map at once, see where the buses are, tap a stop, see when the next bus
  really arrives.
- Out of scope for now: fares, other cities, Android, iPad, widgets, push notifications (they need the paid Apple Developer Program or a server).
- UX is the main goal: it must feel instant and smooth. Live data comes first, the timetable is a fallback.

## Technical context

- Stack (planned): SwiftUI, MapLibre Native (iOS), SQLite for the imported GTFS, SwiftProtobuf for GTFS-Realtime.
  UI strings in English with a maintained Japanese String Catalog.
- Data: see `docs/data-sources.md`. Static GTFS is imported on the device; vehicle positions are polled every 10-15
  seconds and interpolated between polls; trip updates (about 250 KB) are fetched only while a stop is open.
- Offline map: Madison-area OSM vector tiles in one PMTiles file that the app bundles (MapLibre Native reads
  `pmtiles://file://...` itself; verified in the simulator). PMTiles do not take part in MapLibre's offline-pack cache,
  so the app owns the whole file. Any download needs the user's approval (file, source, size, destination).
- Live vs scheduled: the UI must show clearly which times are live and which come only from the timetable.
- Layout: the root `Package.swift` holds the data layer and a tool; `App/` is the iOS app on top of it, generated
  into `Headway.xcodeproj` by XcodeGen from `project.yml` (the project file is not committed).
  - `App/AppModel.swift`: observable app state. Loads the timetable (cache in Application Support, else the bundled
    seed, else a download; refreshes at most daily with a conditional request (ETag / Last-Modified, so an unchanged
    timetable costs a few hundred bytes) and swaps only when the feed version changes), polls vehicles (interval from
    settings), fetches service alerts once a minute, fetches trip predictions (160 KB each, most of the app's data) while a
    stop or bus sheet, the service board or the planner is open, a route is in focus or routes are watched, at most every
    minute for a stop, bus, planner or watched route and every two minutes otherwise, doubled on mobile data and
    quadrupled in Low Data Mode while "Save mobile data" is on and the refresh is Automatic (`AppModel.predictionInterval`,
    `NetworkStatus`; the timetable download waits for Wi-Fi while `timetableOnlyOnWiFi` is on, unless the copy is past its
    end date), recomputes the stop board, and holds
    selection (`ActiveSheet`), the map `focus` (routes, direction, ringed stops and buses) and camera requests.
  - Map overlay: after every parse the route lines, stops and `RouteNetwork` (stops per route and direction, variants
    with their destinations) are saved as a small plist (`App/Map/MapOverlay.swift`, `OverlayStore`). The next launch draws
    every route from it at once while the timetable parses behind it (Debug builds parse in about 3.5 s, Release in about
    0.35 s on a Mac), so the map is never blank. `MapState.overlay` is what is drawn; `schedule` is only used to move buses
    between reports.
  - Lanes: `Sources/HeadwayCore/RouteBundling.swift` (`RouteBundler.overview`) draws the network view. Each route's shapes
    are merged into one line (directions and variants within 30 m; one-way stretches farther apart stay separate), spikes
    to stops are removed, and the lines are laid onto a shared skeleton: a line within 18 m of skeleton already there and
    parallel to it follows that skeleton exactly, so all routes on a street share one centre line (the feed draws each
    a few metres apart, which made lanes wobble). Each skeleton piece knows its routes; lanes go by route order, sides
    are counted along the bundle's first route, runs shorter than about 120 m are dropped, and changes slide over about
    60 m in small steps (or happen at once near a turn). Drawn with a data-driven `line-offset` (the product of `lane`
    and the zoom curve must sit inside the curve's stops or MapLibre raises an exception). A focused route uses the
    per-direction shapes instead (`kind` "d" versus "o"). `feedanalysis overview <zip> <out.geojson>` exports the layout
    to look at in a browser. Raise `MapOverlayData.currentVersion` when this changes; an older saved copy is still drawn
    until the new one is computed (about 0.4 s in a Release build on a Mac, once per timetable). Every piece is a feature
    the map reads and draws at launch, so keep the set small: slides between lanes go in steps of an eighth of a lane
    and one route (a 60 m slide is a few pieces, not 24), and every line is thinned to 1 m (`RouteBundler.simplified`).
    That took the saved copy from 13 MB (90 000 pieces) to 3 MB (23 000) and the launch from 2.5 s to 0.5 s on a Mac;
    `RouteBundlingTests` fails above 15 000 pieces per set. The timings are in the log:
    `xcrun simctl spawn booted log show --info --last 2m --predicate 'subsystem == "dev.kosuke.headway"'` (`launchLog`).
  - Crowding and detail: streets with more than three routes draw thinner lines (`crowd`, down to half; the feature's `k`),
    and from zoom 16 a second set (`detail`, `RouteBundler.overview(merge: 10, snap: 8)`) separates the two directions where
    they run apart; the sets cross-fade at zoom 16 (`a0`/`a1`). A focused route uses `directionLines`, which merge the
    variants of a direction (D1, D2, Verona, Epic Campus) into one line. Line widths, lane gaps, bus markers and journey
    lines all shrink with zoom (`MapLayers.lineZooms`, `busZooms`).
  - Destinations: `RouteNetwork.patterns` (one per route, direction and headsign, with its stops) and
    `MapOverlayData.patternLines` (their lines, only for directions that have several) let the focus chip narrow a route
    to one destination (`MapFocus.headsign`; buses are matched by the headsign of their trip). `AppModel.focusReturn`
    remembers the list a focus was started from (the service info screen, the routes sheet) for the chip's back button.
  - Times: with `showScheduledTimes` (Settings > Times) the stop board and a bus's next stops show the timetable's time and
    how far the live time is from it (`LiveStatus`, `BusSheet`), and the full timetable marks tracked buses with
    `TimeText.delayMark` (+3 / −2). Nothing replaces a timetable time.
  - Delays per bus: `AppModel.refreshStatus` builds `ServiceStatus` and keeps `vehicleDelays` (seconds from the timetable at
    the bus's next stop) while a screen needs them (`needsDelays`: service board, routes list, a focus, a stop or bus
    sheet, the live card); `fleet(route:direction:headsign:)` counts late (over 5 min), on time and early (over 2 min) for
    `FleetCounts`. The trip updates are fetched when such a screen opens (`ensurePredictions`).
  - Buses with no trip: `VehicleSample.tripID` is empty for 5-7 of about 125 buses (out of service, or waiting). They are
    drawn by their own layers (`bus-idle-*`, pale with an orange ring and "!"); `BusNextTrip.of` finds the trip the trip
    updates list for the same bus (`feedanalysis layover` shows it on a recording), and the marker then shows that route
    and its first departure. Their route is not known, so they are not hidden by a focus unless that trip is on another route.
  - Trips with no bus yet: a late bus has no position until it starts its trip, so a trip nobody has seen a bus on would
    vanish from a stop's board the moment its timetable time passed. `Arrivals.upcoming` keeps it in the list of what is
    coming for `Arrivals.unconfirmedGrace` (20 minutes; 7% of trips start more than 5 minutes late, 1% more than 10, 0.3%
    more than 15) unless the trip updates say it is cancelled, and `Arrival.isUnconfirmed(at:)` makes the stop board say
    "No bus seen yet" and how long ago it was due. After that it is "gone" (`Arrival.hasGone(at:)`): nothing is deleted, it
    moves to the earlier departures, and a bus that turns up makes it a live row again. The favourites summary on the
    service board leaves unconfirmed rows out.
  - The stop board (`StopSheet`) reaches back and forward on request: "Earlier departures" (an hour at a time, dimmed rows
    marked "Earlier", with a "Now" line between them and what is coming), "Later departures" (three hours at a time) and
    pull-down to go back to now and refresh (`AppModel.boardEarlier`, `boardWindow`, `resetBoard`; opening another stop
    resets them; "Back to now" also scrolls to the top). The row limit grows with the window (40 per three hours,
    `boardLimit`): with a fixed 40 the second tap on "Later departures" added nothing at a busy stop. Earlier rows carry only
    what the timetable and the current feeds know. Every row opens something: a row with a bus opens the bus, a row with no
    bus opens the trip's own timetable (`TripSheet`, `ActiveSheet.trip`, `AppModel.selectTrip`: all its stops with their
    timetable times, the trip's line on the map; if a bus has turned up on it the bus's sheet opens instead). A bus's sheet
    (`BusSheet`) lists every stop to the terminal (`Arrivals.tripStops`), the ones it has passed greyed out (by the bus's
    `currentStopSequence`, or by time when it does not say) and starts scrolled to the last one passed (`TripStops.swift`).
    The trip sheet does not go into the dock (a timetable has no marker on the map to wait for).
  - Live bus positions are never throttled: not by "Save mobile data", not by the connection. Only the rider's own "Refresh"
    setting (automatic, 30 s, 1 min) changes the vehicle poll, and the larger downloads (`startSlowData`: alerts, trip
    predictions, watched routes) run beside it, one at a time, so that a slow connection cannot delay the positions.
  - The data screen (`App/Sheets/DataSettingsView.swift`, opened by the icon beside "Save mobile data" in Settings > Live
    buses): "Save mobile data", the refresh of predictions on Wi-Fi and on mobile data (`PredictionRefresh`: automatic,
    30 s, 1 min, 2 min, 5 min, manual; `AppModel.predictionInterval`), the timetable on Wi-Fi only
    (`timetableOnlyOnWiFi`), and a data meter (`DataMeter`, `DataUsage`: bytes of response bodies by `DataKind` and by
    Wi-Fi or "metered", `NetworkStatus.isMetered` = expensive or Low Data Mode; `RealtimeClient.onTransfer` reports each
    fetch). Service alerts have no setting: they are 1 KB a minute. Opening a stop, a bus or a list fetches fresh
    predictions at once (`ensurePredictions`, over 30 s old), whatever the refresh setting says.
  - The vehicle poll keeps its place in its cycle in `nextPollAt` and the `poll*` properties: restarting it (a sheet
    opening, a mode change) waits for the scheduled time instead of asking at once and then retrying every two seconds
    (that was up to eight extra 7 KB requests for every sheet opened); only the foreground, the first start and "refresh
    now" ask at once (`restartPolling(immediately:)`).
  - Data use (measured on 2026-10-19 with `nettop` on the simulator, Wi-Fi): a vehicle feed is 7 KB, the alerts 1 KB, the
    trip updates 156 KB (none of them compressed by the city's server). Positions alone cost about 2 MB an hour; with a
    stop open the trip updates, then fetched with every 30 s beat, made it about 22 MB an hour. The vehicle poll asks for
    the next feed `PublishLag.estimate - 1` seconds after its stamp (learned from the feeds seen), not 1.5 s, so that it
    does not download the unchanged feed again every two seconds until the server has published it. After both changes,
    the same measurement with a stop open: trip updates every 60 to 80 s, positions and alerts 16 KB a minute (it was 34),
    7 MB an hour in all. Launch itself downloads nothing but the first vehicle feed (17 KB with the TLS handshake): the map,
    the route lines and the stops are in the app, and the timetable is only asked for when the copy is over a day old.
    `pollLog` (category `poll`) says how old each new vehicle feed was when it arrived (0 to 2 s on a scheduled request) and
    how many requests it took; the city's feed interval was 30 s at night and 35 to 45 s on a weekday morning.
  - Punctuality detail: `PunctualityDetail` (opened from the bars in `StopSheet` through `PunctualityTarget`) draws
    `PunctualityTable.hourly` / `totals` with Swift Charts. Chart pitfalls met here: bars with both ends on both axes must be
    `RectangleMark` (`BarMark` has no such form, and the compiler then says only "failed to produce diagnostic"); a numeric
    axis needs `Double` on every mark, scale and rule (an `Int` domain with `Double` values draws nothing); `width: .ratio`
    needs a category axis.
  - Colours: lateness is red / green / blue and alerts are orange, so the first and last stop of a route are purple and
    black (white on the dark map), and favourite stops are solid dots (`fav` / `size` attributes of the stop layer), not a
    second ring. The map's credits are placed by `MapCoordinator.placeCredits` from the home-bar inset (nothing is changed
    on a phone with a flat bottom edge).
  - Terminals: `RoutePattern.first`/`last` are the stops most trips of a pattern start and end at; `setTerminals` rings
    them (green start, red end) while one route is in focus.
  - Bus markers: the route name and the pattern number from the headsign ("D2") inside, the ring white for trip direction 1
    and black for 0 (mostly east/north and west/south), and a small letter beside it from the feed's `trip_direction_name`
    ("E", "W", "N", "S", "In", "Out"; loops have none). The feed's own `bearing` is not used: a bus changes it at every turn,
    and the trip's direction is what a rider means by "eastbound". A bus moved on from its last report (dead reckoning,
    `DrawnBus.estimated`) has a dashed ring instead of a solid one: a symbol layer per route (`bus-estimate-*`) with
    pre-drawn dashed ring images (`bus-ring-1|0|x`), because a circle layer cannot be dashed; the solid ring layers draw only
    the buses with `est == false`.
  - Opening a bus: `AppModel.selectBus` puts the line of that bus's own trip on the map (`tripFocus`: its route, direction
    and, where the direction has several destinations, only its destination, so D2 shows Epic Campus or Verona, not both).
    It replaces a focus that an earlier bus started (`fromBus`) and one that would hide the bus, but keeps a focus the rider
    chose that already shows it (`AppModel.focus(_:shows:...)`).
  - The dock (`App/Sheets/Dock.swift`): swiping a stop or bus sheet down (the `.sheet` binding's setter in `RootView` calls
    `AppModel.minimizeSheet`), opening the menu or leaving the map puts it into `dockedStopID` / `dockedVehicleID` instead
    of losing it. At the bottom right, stacked, wait one chip per item (bus, stop, journey); a tap or a swipe up brings the
    sheet back, the cross lets go of it (and of the bus's line on the map). The map keeps a docked stop or bus marked
    (`markedStopID`, `markedVehicleID`). The sheet's own cross and a tap on the empty map still close for good. A docked
    bus that stops reporting is dropped.
  - Stops: `cardinal_direction` in stops.txt gives the way each stop's buses go; the stop sheet, search, planner steps,
    the timetable and an arrow beside each stop on the map show it (`Compass`, `AppModel.stopSide`).
  - `Sources/HeadwayCore/ServiceOutlook.swift` (today's first/last trip and the next trip of a route and direction),
    `App/Support/RouteStatusText.swift` (the wording), `Planning/MultiStop.swift` (a trip through up to three stops with
    stay times; each part is planned from the end of the previous one plus the stay, and backwards for "arrive by").
  - Focus: `App/Map/MapFocus.swift`. A focus limits the map to a route (one direction or both), an alert's routes with its
    stops ringed (`StopCodes.find` reads "Stop 7253" out of the alert text, because alerts carry no stop ids) or the late
    and early buses of the delay rows. `Preferences.focusStyle` hides the rest or fades it. Arrows (`route-arrows`,
    `journey-arrows`) show the way buses run; a journey on the map hides everything but itself and the buses of its trips.
  - Notifications: `Sources/HeadwayCore/Watch.swift` (`WatchEvaluator`, `WatchLedger`: late and early are judged per route,
    destination and way (`BusDelay.headsign` / `directionName`), so a late D2 and an early D1 are two messages that name
    their destination, not "D is late" and "D is early"; a whole route (`watchedRoutes`) or single destinations
    (`watchedLines`, `WatchLine`) are watched; late and early after `watchLateMinutes` (3, 5, 10, 15) and `watchEarlyMinutes`
    (1, 2, 3, 5); alerts belong to a route and reach a rider watching any destination of it; each is announced once, and
    late/early again after 45 min; the message is a coloured dot (red late, blue early), the bus and the minutes, with the way
    and the number of buses under it, no sentences),
    `App/Watch/WatchNotifier.swift` (local notifications, `BGAppRefreshTask` `dev.kosuke.headway.watch`). Best effort:
    iOS decides when a background refresh runs.
  - `App/Settings/`: `Preferences.swift` (all user options as one tolerant Codable value, decoding falls back to
    defaults per key), `AppSettings.swift` (observable store in UserDefaults, favourites, recents, reset).
  - `App/Map/`: `MapContainer.swift` (UIViewRepresentable and `MapCoordinator`: applies `MapState` diffs, camera,
    taps), `MapLayers.swift` (sources and layers; routes and stops under basemap labels, buses on top),
    `MapState.swift` (state snapshot, `MapPreferences` subset, `RouteLook`), `BusAnimator.swift` (glide between
    reports).
  - `App/Sheets/`: `StopSheet`, `BusSheet`, `TimetableView`, `RoutesSheet` (one line per direction), `SearchSheet`,
    `SettingsView`, `Components` (route badge, live status, circle button).
  - `App/Support/`: `Formatting.swift` (times, delays, headsigns), `Theme.swift` (map theme, route palettes, colour
    helpers), `LocationController.swift` (permission asked only when the user taps the location button), `Haptics`.
  - `App/Menu/MenuDrawer.swift`: hamburger button and the left drawer (modes Map / Service info / Plan a trip, plus
    shortcuts to routes, search and settings). `AppModel.mode` switches the content; the map stays alive underneath.
  - `App/Info/InfoView.swift`: the service board. `App/Plan/`: `PlanModel` (inputs, results), `PlanView` (inputs, result
    cards, journey detail and steps), `PlacePicker` (stops, favourites, MapKit place search), and
    `App/Sheets/JourneySheet.swift` (summary over the map; the journey is drawn by `MapLayers.setJourney`; the sheet can
    be lowered to a peek but not swiped away, and `JourneyBar` in `RootView` brings it back). A trip that starts or ends at
    a stop may use stops within `PlanOptions.stopAccessMeters` (200 m) of it, so the stop across the street can serve the
    other direction. Saved places are edited in `SavedPlaceEditor`.
  - Map long-press drops a pin and offers directions to or from it; a stop's sheet has a Directions button.
  - `App/RootView.swift`: map, status pill, controls, focus chip, sheet routing (stop and bus share one sheet
    identity so selecting another does not re-present it).
  - Language: Settings > Behavior > Language (system default / English / 日本語, `Preferences.language`). `LanguageState.shared`
    (`App/Support/Language.swift`, observable) holds the chosen language, its `Locale` (the language with the phone's
    region, so units and 12/24 hours still follow the phone) and its `.lproj` bundle; `LanguageRoot` puts the locale into
    the environment for SwiftUI text, and every string built in code goes through `L10n.string`, which reads the chosen
    language's bundle. Never write `String(localized:)` or `NSLocalizedString` in `App/` (`LanguageTests` fails on it): it
    follows the phone's language and ignores the choice. Titles, search prompts and dialog titles passed to UIKit-backed
    SwiftUI views are resolved with `L10n.string` too. The iOS permission text and the app name come from `InfoPlist.strings`
    and keep iOS's language. Map labels stay English (Latin-only glyphs; the feed's names are English).
  - `App/Resources/`: `Localizable.xcstrings` (English keys, Japanese values; add both when adding UI text),
    `ja.lproj`/`en.lproj` InfoPlist strings, `Assets.xcassets` (icon), basemap styles and glyphs.
  - `AppTests/`: Swift Testing for preferences, settings, formatting, colours, map focus and the overlay, notification text.
  - Offline basemap: `tools/fetch_basemap.sh` cuts `data/maps/madison.pmtiles` (17 MB, Protomaps build 2026-10-03,
    zoom 0-15, bbox -89.62,42.93,-89.20,43.20) and fetches Noto Sans glyphs into `App/Resources/glyphs/` (committed,
    0.8 MB). `tools/style/generate.mjs` (Node, `@protomaps/basemaps`; flavors `white` and `dark`, points of interest removed)
    writes both style JSON files; rerun it after changing a flavor. The style has no remote URLs, so the map needs no network. Tiles are bundled into the
    app by `project.yml`, so run `tools/fetch_basemap.sh` before building. Attribution: (c) OpenStreetMap contributors.
  - `Sources/HeadwayCore/Static/`: `CSV.swift` (byte-level CSV scanner), `Models.swift` (Route, Stop, Trip, StopTime,
    ServiceDate), `Schedule.swift` (in-memory static GTFS from a zip or folder; service calendar; trips in progress).
  - `Sources/HeadwayCore/Planning/`: `TripPlanner.swift` (round-based connection scan: for each number of buses the
    earliest arrival, with walking access and footpath transfers, live delays applied to buses that report; a second
    scan finds the buses after the first journey's), `Journey.swift` (journey, legs, polylines along the route shape).
  - `Sources/HeadwayCore/RouteNetwork.swift` (routes per stop, stops and destinations per route and direction),
    `StopCodes.swift`, `Watch.swift`.
  - `Sources/HeadwayCore/ServiceStatus.swift` (per-route and per-bus delays, cancelled trips, trips without a position),
    `Geometry.swift` (distances, nearest point on a line, bus-to-route distance), `Arrivals.swift` (stop board, remaining
    stops of a trip).
  - `Sources/HeadwayCore/Realtime/`: `RealtimeDecoder.swift` (protobuf to plain structs), `RealtimeModels.swift`,
    `RealtimeClient.swift` (async fetch of the three feeds).
  - `Sources/HeadwayCore/Generated/gtfs-realtime.pb.swift`: generated from `proto/gtfs-realtime.proto`; do not edit.
  - `Sources/feedanalysis/`: command-line tool that compares recordings with the timetable (`Report.swift`).
  - `Tests/HeadwayCoreTests/`: Swift Testing. `RealFeedTests` runs only when a downloaded feed exists in `data/feeds/`.
- Important directories: `tools/` (recorder, pull script, helpers), `collector/` (Cloudflare Worker that records the feeds;
  see its README), `docs/`, `proto/`, `data/` (recorded feeds, logs, launchd plist, collector token; outside Git).
- Findings that shape the design are in `docs/data-sources.md`: predictions carry no delay, so delay is computed
  against the timetable; positions can be stale by more than a minute.
- Constraint: free stack only; no paid services. A free personal Apple ID is enough for installing on the user's own
  iPhone (re-signing every 7 days); the paid Developer Program is only needed to distribute (TestFlight, App Store).
- Signing: iOS rejects self-signed certificates (unlike macOS apps), so Headway uses the Apple Development certificate
  of the user's free Personal Team; the team id is kept in the uncommitted `Config/Local.xcconfig`.
  `docs/run-on-iphone.md` has the steps and the TestFlight note.

## Plan

1. Data layer: parse GTFS and GTFS-Realtime, verify against real data, and analyse the 24-hour recording
   (which scheduled trips never get a position).
2. Offline map with all routes and stops.
3. Live bus positions on the map.
4. Stop sheet: live arrivals and timetable.
5. Polish (smoothness, accessibility) and Japanese localization.

## Commands

- Record feeds: `caffeinate -i python3 tools/record_feeds.py --hours 24` (writes `data/feeds/<date>/`). The
  2026-10-03 run was started as a launchd job from `data/launchd/dev.kosuke.headway.recorder.plist` so it survives
  the session; stop it with `launchctl bootout gui/$(id -u)/dev.kosuke.headway.recorder`.
- Smoke test of the recorder: `python3 tools/record_feeds.py --once --no-static`.
- Build: `swift build`; test: `swift test`.
- Analyse a recording: `swift build -c release && .build/release/feedanalysis report data/feeds/<date>`
  (also `schedule <zip>`, `sample <dir>`, `shape <dir>`, `deviation <dir>` (how far buses stray from route lines) and
  `plan <dir> <from> <to> [HH:mm | yyyy-MM-ddTHH:mm]` to try the planner on the real timetable).
- Regenerate protobuf code: `protoc --swift_out=Sources/HeadwayCore/Generated --swift_opt=Visibility=Public -I proto proto/gtfs-realtime.proto`
  (needs `brew install protobuf swift-protobuf`).
- Tools installed with Homebrew for this project: protobuf, swift-protobuf, pmtiles, xcodegen.
- App: `xcodegen generate`, then
  `xcodebuild -project Headway.xcodeproj -scheme Headway -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build/DerivedData build CODE_SIGNING_ALLOWED=NO`.
- Tests: `swift test` (data layer),
  `xcodebuild test -project Headway.xcodeproj -scheme Headway -destination 'platform=iOS Simulator,name=iPhone 18 Pro' CODE_SIGNING_ALLOWED=NO`
  (app; use the simulator's UDID when two are booted) and `cd collector && npm test` (runs the Worker in Cloudflare's
  runtime locally). The counts are in the README's Quality checks; update them there when tests are added.
- Strings: `tools/add_strings.py` adds or updates Japanese translations in the catalog from JSON on stdin.
- iPhone: `tools/run_on_device.sh` builds a Release build (the timetable loads about ten times faster than in Debug).
- Collector: `collector/README.md` (setup, limits, taking it down); `python3 tools/pull_feeds.py [--status]` fetches what it
  recorded into `data/feeds/`.
- Before building the app: `tools/fetch_basemap.sh` and `tools/fetch_timetable.sh` (both outputs are bundled by
  `project.yml` and not committed), then `xcodegen generate`.
- Icon: `swift tools/make_icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset` (light, dark, tinted).
- Simulator notes: `simctl ... booted` can point at the wrong device when two are booted; use the UDID. Typing into
  a search field through the control tool is slow; wait before the next tap.
- The 24 h feed report is written by a launchd job (`data/launchd/dev.kosuke.headway.report.plist`) to
  `docs/feed-analysis-2026-10-03.md` at 2026-10-04 17:10 CDT.
- Recordings run continuously: the Cloudflare collector records, and the launchd job `dev.kosuke.headway.pull` (hourly,
  `tools/pull_feeds.py`) writes them to one folder per day in `data/feeds/` (about 15 MB a day); the collector keeps only
  6 days. The jobs must be loaded from `~/Library/LaunchAgents` (copies of `data/launchd/*.plist`): a job loaded straight
  from `data/launchd/` is forgotten at the next restart, which lost four days in October 2026. Check after any restart:
  `launchctl print gui/$(id -u)/dev.kosuke.headway.pull` and `python3 tools/pull_feeds.py --status`. A nightly job (04:30)
  runs `tools/build_punctuality.sh`, which turns recorded bus positions into observed arrival times (SQLite,
  `data/punctuality/observations.sqlite`) and exports `data/punctuality/punctuality.json`, which the app bundles.
  `feedanalysis freshness|accuracy|punctuality` explain the feed's real latency, prediction accuracy and punctuality;
  `early` (what the predictions said about arrivals that were early or late) and `notstarted` (predictions for trips whose
  bus is still on its previous trip) answer the two questions that came up from riding; their results are in
  `docs/data-sources.md`.
- Format, lint: not set up yet.

## Known limits and next steps

- Runs on the author's iPhone 12 Pro; Dynamic Type, VoiceOver on the map, and low-power behaviour are unchecked. The
  simulator ignores the first tap after a screen change in some cases; tap twice or wait before checking.
- Predictions come from the city's trip-updates feed, which has no delay field and covers only trips with a bus;
  the board therefore shows the timetable for the rest. Whether predictions are biased is unverified (see
  `docs/data-sources.md`).
- The city's feed has stalled and lagged since about 2026-10-20 (a stamp standing still for 90 s, positions 60 to 90 s behind
  it), but that does not explain a rider's "168 s old" with Refresh doing nothing on mobile data. The likely cause was in
  the app: up to 0.6.2 the vehicle poll waited for the trip-update download. Also fixed: the poll stopped while the app was
  merely "inactive", sheet and mode changes cancelled the request under way, an older feed could replace a newer one, and a
  watchdog now restarts a poll that has not been answered for 30 s. See `docs/data-sources.md`, "When positions are a minute
  or two old". The live card says whether the city's feed or the phone's connection is behind.
- Live latency (measured on 2026-10-03, see `docs/data-sources.md`): a bus reports every 30 s, the feed is rebuilt every
  30 s, positions are about 25 s old on arrival. The app times its requests from the server's `Date` header, dead-reckons
  buses along their route at their last speed (up to 50 s), and veils buses silent for over 75 s (45 s beyond the fleet's median age when the whole feed is behind,
  `MapLayers.staleLimit`). Predictions are
  accurate to about +/-40 s (median) within 5 minutes and barely better than the timetable beyond 20 minutes.
- Punctuality statistics need weeks of recordings to be reliable; the app says how many days they cover and shows
  nothing for a route and time of week with too few observations.
- Detour paths are not published by the city (the alerts have text, a link to its detour page, and a period). Buses on
  routes with an alert were mostly on their normal line in the first recording, so inferring detour paths from live
  positions is not reliable yet; the app dashes affected routes and rings buses that are off their line.
- Trip planner: walking is a straight line scaled by 1.3 (no street network offline); places by name need Apple Maps
  (online); the search looks 4 hours ahead.
- Routes have several destinations per direction (a weekday-only branch such as "2-Epic Campus" next to "2-Verona"); the
  lists show the most common ones. A recording that covers only a weekend does not contain the weekday-only trips.
- Notifications are local only (no server, no paid account): they depend on the app running or on iOS granting a
  background refresh, which is usually every 15 minutes to a few hours and not at all for an app that is rarely opened.
  Real push needs the paid Developer Program (APNs) or a relay such as ntfy fed by the collector; neither is built.
- Bus markers trail the real bus by up to one update interval plus the feed's own latency.
- Versions: `0.MINOR.PATCH` (semantic versioning; the project is below 1.0). A batch of fixes gets the next patch
  (0.3.0 to 0.3.1) and a new feature or a visible change gets the next minor (0.3.x to 0.4.0); both are tagged `vX.Y.Z`
  (annotated, the message says what changed) right after the commit, with `MARKETING_VERSION` and
  `CURRENT_PROJECT_VERSION` in `project.yml` raised to match. Patch tags need no asking. 1.0.0 is for the owner to
  decide. Tags and releases are pushed only when pushing is allowed (see the owner's repository notes).
- Publishing: the data terms contain an indemnification clause (see `docs/data-sources.md`); the App Store needs the
  paid Developer Program; map tiles need the OSM attribution (already in Settings and the map's info button).
- Ideas not started: notifications when a bus is near, a push relay fed by the collector, widgets, other cities (GTFS is generic, the feed URLs and
  basemap box are the Madison-specific parts), iPad layout.

## Definition of done

- The requested behaviour is complete, including loading, empty, offline and error states.
- Formatting, linting, tests and builds pass where configured.
- UI is checked in the iOS Simulator at representative sizes and in light and dark mode.
- Accessibility (Dynamic Type, VoiceOver, contrast) is checked.
- Documentation matches what was delivered.
