# Third-party material

Headway's own code is under the MIT licence (`LICENSE`, Copyright (c) 2026 Kosuke Satake). The material below belongs to
others and keeps its own terms. Everything that ships in the app is also listed, with its full licence text, in
Settings > Licences (the texts are `App/Resources/Licenses/*.txt`; `LicenseTests` checks that each one is present).

No copyleft licence (GPL, AGPL, LGPL) and no non-commercial or no-derivatives licence (CC BY-NC, CC BY-ND) is used. Apple's
own frameworks (SwiftUI, MapKit, CoreLocation, Swift Charts, UserNotifications, BackgroundTasks) are part of the system and
need no entry.

## Shipped in the app

| What | Where | Licence |
|---|---|---|
| [MapLibre Native](https://github.com/maplibre/maplibre-native) (map rendering) | Swift package dependency, via maplibre-gl-native-distribution 6.31.0 | BSD 2-Clause |
| [SwiftProtobuf](https://github.com/apple/swift-protobuf) 1.38.1 (reads the live feeds) | Swift package dependency | Apache License 2.0 |
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) 0.9.20 (opens the timetable archive) | Swift package dependency | MIT |
| `gtfs-realtime.proto` and the Swift code generated from it | `proto/`, `Sources/HeadwayCore/Generated/` | Apache License 2.0, Copyright 2015 The GTFS Specifications Authors |
| Noto Sans glyphs (map label fonts, as `.pbf` files) | `App/Resources/glyphs/`, fetched by `tools/fetch_basemap.sh` from [protomaps/basemaps-assets](https://github.com/protomaps/basemaps-assets) | SIL Open Font License 1.1; the text is `App/Resources/glyphs/OFL.txt` and is bundled with the fonts |
| Map styles `basemap-light.json` and `basemap-dark.json`, generated from [@protomaps/basemaps](https://github.com/protomaps/basemaps) | `App/Resources/` | BSD 3-Clause (code); the visual design is CC0, some icons MIT (Mapzen); the text is `App/Resources/Licenses/protomaps-basemaps.txt` |
| Map data | `data/maps/madison.pmtiles` (not in the repository; built by `tools/fetch_basemap.sh`) | © OpenStreetMap contributors, Open Database Licence 1.0; tiles from a Protomaps build |
| Timetable and live feeds | City of Madison, WI, Metro Transit | Terms in the feed's `terms_of_use.txt`, summarised in `docs/data-sources.md`; not in the repository |

The app shows the OpenStreetMap and City of Madison credits in Settings, in Settings > Licences and on the map.

## Used to build and test, not shipped

| What | Where | Licence |
|---|---|---|
| [@protomaps/basemaps](https://github.com/protomaps/basemaps) 5.7.2 | `tools/style/` (Node; generates the map style) | BSD 3-Clause |
| [wrangler](https://github.com/cloudflare/workers-sdk), [@cloudflare/workers-types](https://github.com/cloudflare/workerd), [TypeScript](https://github.com/microsoft/TypeScript) | `collector/` dev dependencies (the recorder's Worker) | MIT or Apache-2.0 (wrangler, workers-types); Apache-2.0 (TypeScript) |
| XcodeGen, pmtiles | command-line tools named in the README | MIT (XcodeGen), BSD 3-Clause (go-pmtiles) |

Checked on 2026-10-10 against the licence files of the checked-out packages (SwiftProtobuf, ZIPFoundation, MapLibre), the
`license` field of the installed Node packages, and the licence text published in the protomaps/basemaps repository.
