# Data sources: Madison Metro Transit

Checked on 2026-10-03 by fetching the feeds and decoding them with `HeadwayCore`.

| Data | URL | Notes |
|---|---|---|
| Static GTFS | `https://transitdata.cityofmadison.com/GTFS/mmt_gtfs.zip` | 7.3 MB, feed `S072_202608240858`, valid 2026-08-16 to 2026-12-05, no key |
| Vehicle positions (GTFS-RT) | `https://metromap.cityofmadison.com/gtfsrt/vehicles` | about 3 KB, no key |
| Trip updates (GTFS-RT) | `https://metromap.cityofmadison.com/gtfsrt/trips` | about 250 KB, no key |
| Alerts (GTFS-RT) | `https://metromap.cityofmadison.com/gtfsrt/alerts` | about 3 KB, no key |

Developer page: <https://www.cityofmadison.com/metro/business/information-for-developers>.
The older `transitdata.cityofmadison.com/{Vehicle,TripUpdate,Alert}/*.pb` URLs return 13-byte empty files.

## Terms of use (`terms_of_use.txt` inside the feed)

Read on 2026-10-03 and compared again with the file in the feed on 2026-10-10; this is a summary, not legal advice.

- The license is non-exclusive, limited and revocable. Use, reproduction and redistribution are allowed, limited to
  uses that assist transit riders or promote public transportation.
- Crediting the city is optional. The wording if used: "Data provided under license granted by City of Madison, WI,
  Metro Transit."
- "Data" includes anything derived from what the licensee receives, and the city keeps all rights in the Data (except
  those of third parties). Headway's punctuality statistics are derived from the feeds, so they are published as the
  statistics of the app and not as a dataset; the recordings themselves (`data/`) are never committed or redistributed.
- The data is provided as is, with no warranty of accuracy or availability. The agreement is governed by Wisconsin law.
- The licensee indemnifies the city against claims arising from its use of the data or products derived from it.
  Think about this before publishing the app on the App Store.
- The city may modify, terminate or revoke the agreement at any time.

## What the static feed contains

29 routes (with brand colours), 1,681 stops, 14,199 trips, 603,662 stop times, 184 shapes (about 180,000 points), and
12 service calendars with exceptions. `stop_times.txt` alone is 38 MB of text. Parsing the whole feed in memory
takes about 2 s in a debug build, so the app will import it into SQLite once instead of parsing on every launch.

## What the realtime feeds contain (one snapshot, 2026-10-03 17:01 CDT)

- Vehicles: every vehicle has `trip_id`, `route_id` and `vehicle_id`; none has `stop_id` or `current_stop_sequence`,
  and `direction_id` and `start_date` are empty. Position timestamps were 11 to 85 s older than the feed timestamp.
- Trip updates: 126 of 130 entities have a `trip_id`; 68 have a `vehicle_id` (trips with a bus already assigned).
  All are `SCHEDULED`. `delay` fields are never set, only absolute predicted times, so delay has to be computed
  as predicted time minus timetable time.
- Alerts: detours such as "L - Aberg RR Detour" and "80 - Randall Detour", with route ids.

## Preliminary findings (35 minutes, Saturday afternoon; not conclusive)

From `feedanalysis report` on the first 35 minutes of the recording:

- About 95% of scheduled trips in progress had a bus position; about 5% had none (route R and 80 stood out, on very
  few samples). No trip was found with an assigned bus but no position.
- About 2% of bus observations came from vehicles reporting no trip id.
- Positions older than 60 s: about 1%.
- Predicted arrival at the next stop minus the timetable: median +92 s, p95 +655 s, about 23% more than 5 minutes
  late, none more than 5 minutes early. This may be real lateness or a systematic offset in how predictions are
  built; it is not verified. The 24 h report (`docs/feed-analysis-2026-10-03.md`, written automatically) is the
  better basis.

## How live the feed really is (measured 2026-10-03 from 728 fetches)

| | median | p90 |
|---|---:|---:|
| a bus reports every | 30 s | 36 s |
| the server rebuilds the feed every | 30 s | 41 s |
| age of a position inside the feed | 11 s | 20 s |
| age of the feed when fetched at random | 15 s | 31 s |

So a position on screen is about 25 s old on average and can be nearly a minute old. About half of the fetches of a
10-second poll returned the same data. The response has a `Date` header (the server's clock), which the app uses to
fetch right after each rebuild.

Measured again on 2026-10-18 over all recordings of 2026-10-03 to 2026-10-08 (13,173 fetches, 152 buses with at least
20 reports; `feedanalysis freshness data/feeds`): every bus has the same typical interval (each bus's median is 30 to 32 s),
but single intervals vary. 68% are 25 to 35 s, 13% are shorter, 16% are 35 to 50 s, 3% are 50 to 90 s and 0.6% are 90 s or
more. The feed itself changes every 30 s at the median (p90 39 s). "About every 30 seconds" is therefore right for every bus,
and an interval of up to a minute is not unusual.

## How good the live predictions are (first 3 hours of recordings, Saturday evening)

Predicted arrival at a stop compared with the arrival observed afterwards from bus positions (error in seconds, median
absolute / 90th percentile, by how far ahead the prediction was made):

| ahead | live prediction | timetable |
|---|---|---|
| 0-2 min | 21 / 73 | 117 / 429 |
| 2-5 min | 42 / 132 | 120 / 431 |
| 5-10 min | 65 / 193 | 121 / 429 |
| 10-20 min | 93 / 270 | 123 / 429 |
| 20-30 min | 112 / 335 | 130 / 435 |

The timetable runs about 100 s earlier than reality on average (bias -100 s); live predictions have almost no bias
close in. Observed punctuality over the same hours: about 11% of arrivals more than a minute early, 70% on time,
19% more than five minutes late. Regenerate with `feedanalysis accuracy data/feeds`.

No public history of on-time performance by stop was found (the city publishes ridership and annual reports), so the
statistics are built from the project's own recordings.

## Early buses, holding at stops, and trips whose bus has not started (checked 2026-10-18)

Recordings 2026-10-03 to 2026-10-08; observed arrivals are the 230,730 of 2026-10-03 to 2026-10-07 in
`data/punctuality/observations.sqlite` (the bus's position projected onto its route, so each arrival is good to about
half a minute).

- How early buses run: 6.6% of arrivals were more than 2 minutes early, 3.4% more than 3, 1.2% more than 5. 13% were more
  than 5 minutes late. Very early buses exist but are rare.
- Holding at timepoints is not visible in the data. At the 14% of stops that `stop_times.txt` marks as timepoints, buses
  were not less often early than at other stops (15.6% more than a minute early, against 13.3%), and a bus that arrived
  more than 2 minutes early at a timepoint was still a median 192 s early at the next stop (the lead changed by 12 s). A
  bus that waits would show up as a lead that shrinks. The 30-second position reports cannot show a short wait directly.
- Dwell time and skipped stops cannot be measured with this feed: vehicle positions carry no stop id or status
  (`current_status`), and a typical stop lasts less than the 30 s between reports. The `SKIPPED` flag in trip updates marks
  stops the service skips (detours), not stops where nobody got on or off.
- The live predictions do follow early buses: for arrivals that were more than 3 minutes early, the predictions made 0 to
  10 minutes ahead implied a median 145 s ahead of the timetable (`feedanalysis early data/feeds`).
- Trips whose bus has not started them: 31% of the predictions that have an assigned bus are for a trip whose bus is still
  on its previous trip. Their error is only a little smaller than the timetable's (median 72 s against 83 s, p90 243 s
  against 290 s), and they under-report lateness: for arrivals more than 5 minutes late the implied delay was a median
  156 s (a bus already on the trip: 365 s). Predictions for buses already on the trip: median error 64 s against 123 s
  for the timetable (`feedanalysis notstarted data/feeds`). Of 86 buses on a trip in one snapshot, 27 had the next trip
  listed.
- Late starts: at the first observed stop, 7.3% of trips were more than 5 minutes late, 0.9% more than 10, 0.3% more than
  15; 2.7% of trips in progress had no bus position at all. A trip that has no bus yet is the one that looks "gone" on a
  stop's board once its timetable time has passed.

## Alerts

Nine alerts on 2026-10-03, all with effect `DETOUR`, a description, a link to a city detour page and a coarse active
period (whole days; the text has the real hours). They name routes, not stops, even when the text says a stop is
closed. There is no geometry. Moving buses were within a few metres of their route line on almost every route, including
routes with alerts (the detours are limited in time), so a detour path cannot yet be recovered from positions.

## Directions and destinations (checked 2026-10-04 in feed S072_202608240858)

Each trip has a `direction_id` (0 or 1), a `trip_direction_name` ("Westbound", ...) and a headsign that begins with a
pattern number ("2-Airport"); the number is part of what the bus displays. A route can show several headsigns in one
direction. Route D, for example:

| direction | headsign | trips | runs on |
|---|---|---:|---|
| 0 | 1-JUNCTION | 279 | every day |
| 0 | 2-EPIC CAMPUS | 149 | Monday to Friday only |
| 0 | 2-VERONA | 130 | every day |
| 0 | 2-WILLIAMSBURG | 7 | weekends |
| 0 | 1-GAMMON, 2-MCKEE | 5 each | weekdays |
| 1 | 2-AIRPORT | 286 | every day |
| 1 | 1-SPRECHER | 275 | every day |
| 1 | INGERSOLL, 1-DEMPSEY | 12, 4 | some days |

So a D bus can say "2-Epic Campus" on a weekday while the app, on a weekend, lists only "2-Verona" for the same stop;
both are in the timetable. Whether the city changed D recently cannot be told from one feed version. The recordings so far
cover a weekend, so the weekday patterns could not yet be checked against buses (`feedanalysis variants data/feeds <route>`
compares the headsign of each bus's trip with the line it is on). Many Madison streets are one-way, so the two directions
of a route often use different streets and stops.

## Open questions

- Do the preliminary numbers above hold over a full day, and do they differ by hour and route?
- Are predictions biased late? Compare predicted and observed arrival times (needs positions near stops).
