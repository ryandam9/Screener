# Stocks Analysis

A Flutter app that reads the growth-screener SQLite databases published to
`s3://hive-in-the-cloud` and renders them on device. One codebase serves a
handset layout and a desktop layout, chosen from the window width.

The two files — `us.db` (US stocks) and `asx.db` (ASX ETFs) — are downloaded
over HTTPS, cached locally, and queried with `sqflite`. Everything except the
refresh works offline.

## Screens

The layout switches at 900 logical pixels: below it, bottom navigation and one
column; above it, a sidebar and a multi-column dashboard. Resizing the desktop
window moves between them live, and every list and query is shared — only the
navigation chrome and the dashboard differ.

| Screen | What it shows |
| --- | --- |
| **Dashboard** | Handset: a card per market, the strongest movers, and recent runs. Desktop: four summary cards, a Top Gainers table with the full column set, median growth per window charted per market, plus Recent Analyses and Top Movers panels. |
| **Markets** | The full instrument list with sortable columns, search, and filters for exchange and minimum change. Tabs: All Stocks, Top Movers, Consistent, Watchlist. |
| **Stock detail** | Price, change, and the window's endpoints; a price chart; the full published metric set; every window compared; and the Google Finance links carried in the data. |
| **Watchlist** | Starred tickers from both markets, swipe to remove. |
| **Analysis** | Run-level statistics: instrument count, median/strongest/weakest change, a distribution histogram, a per-exchange breakdown, and the most traded instruments. |
| **Reports** | Every published run with its row count, `data_as_of` and `run_id`, and a CSV export per window. Desktop shows it in the sidebar; the handset reaches it from More. |
| **More / Settings** | Per-file sync status and size, re-download and cache controls, theme, and row density. |

## Data

### Source

```
https://hive-in-the-cloud.s3.ap-southeast-2.amazonaws.com/us.db
https://hive-in-the-cloud.s3.ap-southeast-2.amazonaws.com/asx.db
```

The bucket lives in `ap-southeast-2`. The regional host matters: the generic
`s3.amazonaws.com` host answers `301 PermanentRedirect` for it. The base URL
lives in `DbSyncService` and can be overridden at runtime.

### Schema

Each file holds one table per look-back window, plus `consistent_growth_stocks`.
The table *prefix differs between the two files*, so nothing is hard-coded —
`MarketDatabase.open` reads `sqlite_master` and maps physical tables to windows
by suffix:

| File | Tables |
| --- | --- |
| `us.db` | `us_stocks_growth_{7_days,1_month,3_months,6_months,1_year}` |
| `asx.db` | `asx_etf_growth_{7_days,1_month,3_months,6_months,1_year}` |

Every growth table carries the same columns:

```
ticker, name, exchange, asset_type, first_date, first_price, last_date,
latest_price, pct_change, observations, days_covered, coverage,
observation_ratio, median_volume, price_basis, data_as_of, run_id,
google_finance
```

A window's table can be empty (ASX has no 3-month rows in the current run), and
`consistent_growth_stocks` may be absent or empty. Both cases are handled with
explanatory empty states rather than errors.

### What the data does *not* contain

Two things in the original design have no backing data, and the app is explicit
about it rather than inventing numbers:

- **No daily price bars.** Each row stores only its window's opening and closing
  price. The detail chart therefore plots exactly the prices the database
  states: one point per window start, plus the close. Each point is marked, and
  a caption says the line between them is a straight join, not a price path.
  A 7-day chart is legitimately just two points.
- **No index level.** There is no ASX or S&P value to show, so each market card
  leads with the *median percentage change* for the selected window over the
  instrument count, and its sparkline is that median across every window.

### Design deviations

- **"Losers" tab → "Consistent".** These files are growth screens; the smallest
  7-day change in `us.db` is +10.04%. A Losers tab would always be empty, so its
  slot shows `consistent_growth_stocks` — tickers that grew in every window.
- **Detail tabs.** "History" and "News" become **Windows** (every window's
  figures and coverage for the ticker) and **Links** (the published Google
  Finance URLs and run provenance), which is what the data supports.
- **Derived metrics are labelled as derived.** "Momentum" compares the shortest
  window's percentage gained *per covered day* against the longest window's,
  and the volume badge is a percentile within the same window rather than an
  absolute threshold — ASX ETF turnover and US stock turnover are orders of
  magnitude apart.

The desktop mockup asks for four more things the data cannot support:

- **No market-session countdown.** Nothing in the files describes trading
  hours, so the sidebar card reports what the app does know — whether both
  databases are current and how fresh the run is — over a live local clock.
- **No month-on-month deltas.** Each file carries a single `run_id`, so there
  is no earlier run to compare against. The Analysis Summary card shows the
  run's totals and says "no earlier run to compare against" instead of an
  invented "+23%".
- **No dated market trend.** The "Market Trend" chart plots a dated index
  series. With only window endpoints published, the desktop chart plots median
  percentage change *per look-back window* (7D through 1Y), one line per
  market, and labels the axis accordingly.
- **No "today" movers and no user account.** The shortest window is seven days,
  so that panel is "Top Movers (shortest window)"; the account chip is replaced
  by the sync status and a refresh button, since the app has no accounts.

Counts are labelled for what they are: the Analysis Summary "Rows" figure sums
rows across every window, so a ticker present in five windows contributes five
rows — it is not a distinct instrument count.

## Architecture

```
lib/
  models/       Market, GrowthWindow, StockRow, PriceSeries
  data/         DbSyncService (S3 + cache), MarketDatabase (discovery + queries)
  state/        AppState (sync/selection), WatchlistController, SettingsController
  theme/        ScreenerColors theme extension, light and dark palettes
  ui/           responsive.dart picks the layout
                screens/  shared screens plus the handset shell
                desktop/  sidebar shell, dashboard and its widgets
                widgets/  chart, sparkline, tiles, panels
```

Sync is offline-first. On start each cached file is opened and shown
immediately, then refreshed with a conditional `GET`; a `304` leaves the cache
untouched. A download is streamed to `<file>.part`, checked for the SQLite magic
header, and renamed into place only if valid — so a failed or corrupted refresh
can never destroy a working database. If the refresh fails outright, the open
database keeps serving and the UI says it is showing cached data.

## Building

Requires the Flutter SDK (developed against 3.47.1 / Dart 3.13).

### Android

```bash
flutter pub get
flutter run                      # debug, on a connected device or emulator
flutter build apk --release      # APK
flutter build appbundle --release
```

The release build is signed with the debug key by default; add a real signing
config in `android/app/build.gradle.kts` before distributing.

`android.permission.INTERNET` is declared in the main manifest — Flutter only
adds it to the debug and profile manifests, so a release build without it would
fail to reach S3.

### Linux

The same code runs as a Linux desktop app. The window opens at handset width
(420x880) so it starts on the phone layout; widening it past 900px switches to
the sidebar layout live.

```bash
sudo apt-get install libgtk-3-dev   # plus clang, cmake, ninja-build, pkg-config
flutter build linux --release
./build/linux/x64/release/bundle/screener
```

`sqflite` ships an Android plugin but no desktop implementation, so
`configureDatabaseFactory()` in `lib/data/sqlite_platform.dart` swaps in the FFI
factory (backed by the system SQLite) when running on Linux, Windows, or macOS.
Nothing else in the app is platform-specific.

## Tests

```bash
flutter analyze
flutter test
```

75 tests cover the table discovery and every query (against fixture databases
built to the published schema, including the differing prefixes), the price
series assembly, the sync service (conditional requests, progress, corrupt
downloads, failure handling), the formatters and trend classifier, CSV
rendering and the export's write path, opening the published Google Finance
links, and both layouts driven end to end against a fake S3 — including that a
wide window gets the sidebar and a narrow one does not.

Five of those are the real-data tests below; they report as skipped unless
`SCREENER_DB_DIR` is set, so a plain `flutter test` shows `+70 ~5`.

To additionally verify the data layer against the real published files:

```bash
mkdir -p .cache
curl -o .cache/us.db  https://hive-in-the-cloud.s3.ap-southeast-2.amazonaws.com/us.db
curl -o .cache/asx.db https://hive-in-the-cloud.s3.ap-southeast-2.amazonaws.com/asx.db
SCREENER_DB_DIR=.cache flutter test
```

Those tests skip themselves when `SCREENER_DB_DIR` is unset, so an offline run
still passes.

## Disclaimer

Figures are screener output — window endpoints, not live quotes — and are not
investment advice.
