# Privacy

Headway has no account, no analytics, no advertising and no server of its own. Nothing about you or your phone is sent
to the author. This was checked against the source on 2026-10-10 (every network address in the code is listed below).

## What stays on your phone

- **Your location**, if you allow it ("While Using the App"). It shows where you are on the map, finds nearby stops, and
  starts a trip "from my location". It is read by the app on the phone and is never sent anywhere by Headway.
- **Your choice of language** (Settings > Behavior > Language). It is one more setting and stays on the phone like the rest.
- **Your settings, favourite stops and routes, saved places (Home, Work, ...), saved and recent trips, and the routes you
  watch.** They are stored in the app's own storage on the phone (they are part of an iCloud or computer backup of the
  phone if you make one) and nowhere else. "Reset settings" clears the settings and keeps the favourites.
- **A data meter** (Settings > Live buses > the icon next to "Save mobile data"): how many bytes of each kind the app has
  downloaded, on Wi-Fi and on mobile data, since a date you can reset. It is counted by the app and stays on the phone.
- **Notifications** about watched routes and trip reminders are scheduled on the phone. Headway does not use push
  notifications.

## What goes over the network

| To | What | Why |
|---|---|---|
| `transitdata.cityofmadison.com` (City of Madison, WI) | a request for the timetable file (at most once a day; it asks first whether the file changed; by default only on Wi-Fi, which can be changed in Settings > Mobile data) | the bus timetable |
| `metromap.cityofmadison.com` (City of Madison, WI) | requests for the live bus positions (about every 30 seconds while the app is open), trip predictions (at most about once a minute, and only while something that needs them is open) and service alerts (once a minute) | live buses and arrival times |
| Apple Maps (MapKit local search) | the text you type when you look for a place by name in the trip planner, with a fixed search area around Madison (not your position) | finding places for a trip; handled under Apple's privacy policy |

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
