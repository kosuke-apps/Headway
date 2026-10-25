# Privacy

Headway has no account, no analytics, no advertising and no server of its own. Nothing about you or your phone is sent
to the author. This was checked against the source on 2026-10-25, for version 0.7.5 (every network address in the code is
listed below), and a running copy's connections were watched for 20 minutes the same day: all of them went to the City's
live-bus address below.

## What stays on your phone

- **Your location**, if you allow it ("While Using the App"). It shows where you are on the map, finds nearby stops, and
  starts a trip "from my location". It is read by the app on the phone and is never sent anywhere by Headway.
- **Your choice of language** (Settings > Behavior > Language). It is one more setting and stays on the phone like the rest.
- **Your settings, favourite stops and routes, saved places (Home, Work, ...), saved and recent trips, the routes and single
  destinations you watch, and how late or early a bus must be before you are told.** They are stored in the app's own storage on the phone (they are part of an iCloud or computer backup of the
  phone if you make one) and nowhere else. "Reset settings" clears the settings and keeps the favourites.
- **A data meter** (Settings > Live buses > the icon next to "Save mobile data"): how many bytes of each kind the app has
  downloaded, on Wi-Fi and on mobile data, since a date you can reset. It is counted by the app and stays on the phone.
- **Notifications** about watched routes and trip reminders are scheduled on the phone. Headway does not use push
  notifications. The small picture that comes with a late or early notification is drawn by the app on the phone and
  kept in a temporary file for iOS to show; it is not downloaded and nothing about it is sent.

## What goes over the network

| To | What | Why |
|---|---|---|
| `transitdata.cityofmadison.com` (City of Madison, WI) | a request for the timetable file (at most once a day; it asks first whether the file changed; by default only on Wi-Fi, which can be changed in Settings > Mobile data) | the bus timetable |
| `metromap.cityofmadison.com` (City of Madison, WI) | requests for the live bus positions, trip predictions and service alerts (details below) | live buses and arrival times |
| Apple Maps (MapKit local search) | the text you type when you look for a place by name in the trip planner, with a fixed search area around Madison (not your position) | finding places for a trip; handled under Apple's privacy policy |

How often the app asks the City:

- **Live bus positions** (about 7 KB each): right after the City's feed is due, which has been every 30 to 45 seconds. When
  the feed is late it asks again every 2 seconds, up to 8 times, and then every 10 seconds; if nothing has answered for 30
  seconds it starts over. It keeps asking while the app is in front, also while iOS has it "inactive" (Control Center, a
  system alert), and stops in the background unless you turned off "Pause in the background". Your own "Refresh" setting
  (automatic, 30 seconds, 1 minute) is the only setting that changes this, and "Refresh now" asks at once.
- **Trip predictions** (about 160 KB each, the largest part of what the app downloads): about once a minute while a stop, a
  bus, the planner or a watched route needs them and every two minutes otherwise; slower on mobile data while "Save mobile
  data" is on (Settings > Mobile data can set it to 30 seconds, 1, 2 or 5 minutes, or only when you refresh). Opening a stop, a bus or a list asks for fresh ones at once if the last copy is more than 30 seconds old.
- **Service alerts** (about 1 KB): once a minute.

A link you tap (an alert's page about a detour, the OpenStreetMap copyright page) opens in your browser; the app does not
load it itself.

The requests to the City carry no identifier and no location: they ask for the same public files for everyone. The
City's servers can see your phone's network address, as any web server can. The map itself (OpenStreetMap data) is stored
in the app, so looking at the map sends nothing.

## Permissions

- **Location (While Using the App)**: described above. Without it, everything works except "my location".
- **Notifications** (optional, asked for the first time you watch a route or set a reminder): to tell you that a watched
  route is late, early or has an alert, and when to leave for a trip.
- **Background refresh**: lets iOS wake the app now and then to check the routes you watch. It can be switched off in
  iOS Settings.

## The recordings behind the punctuality figures

The author runs a separate recorder (the `collector/` folder: a Cloudflare Worker on the author's own account plus a job on
the author's Mac) that saves the City's public feeds every minute, to work out how punctual each route usually is. It
records only the public feeds; it never sees anything from anybody's phone. The resulting statistics are built into the
app. The recordings are not published.

## Contact

Questions about privacy: open an issue at <https://github.com/kosuke-apps/headway/issues>.
