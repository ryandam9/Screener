# Stocks Analysis

A Flutter app that reads the growth-screener SQLite databases published to
`s3://hive-in-the-cloud` and renders them on device. One codebase serves a
handset layout and a desktop layout, chosen from the window width.

The files — `us.db` (US stocks), `asx.db` (ASX ETFs) and `nse.db` (NSE India
stocks) — are downloaded over HTTPS, cached locally, and queried with
`sqflite`. Everything except the refresh works offline.

## Screens

The layout switches at 900 logical pixels: below it, bottom navigation and one
column; above it, a sidebar and a multi-column dashboard. Resizing the desktop
window moves between them live, and every list and query is shared — only the
navigation chrome and the dashboard differ.

| Screen | What it shows |
| --- | --- |
| **Dashboard** | Handset: a card per market, the strongest movers, and recent runs. Desktop: four summary cards, a Top Gainers table with the full column set, a weekly price chart for the selected security, plus Recent Analyses and Top Movers panels. |
| **Markets** | The full instrument list with sortable columns, search, and filters for exchange, category, issuer and minimum change. Tabs: All Stocks, Top Movers, Consistent, Watchlist. |
| **Stock detail** | Price, change, and the window's endpoints; a weekly price chart for the selected window; the full published metric set; every window compared; and the Google Finance links carried in the data. |
| **Watchlist** | Starred tickers from every market, swipe to remove. A starred ticker is tinted wherever else it is listed. |
| **Analysis** | Run-level statistics: instrument count, median/strongest/weakest change, a distribution histogram, a per-exchange breakdown, and the most traded instruments. |
| **Reports** | Every published run with its row count, `data_as_of` and `run_id`, and a CSV export per window; below each market, the run metadata behind that file and its screen funnel. Desktop shows it in the sidebar; the handset reaches it from More. |
| **Price history** | Every ticker the run collected, not just what passed a screen, with a chart of its published bars. Search plus category and issuer filters where the file labels its tickers. It is a primary navigation area on both handset and desktop, and always names the selected market. |
| **More / Settings** | Per-file sync status and size, re-download and cache controls, theme, and row density. |

## Data

### Source

```
https://hive-in-the-cloud.s3.ap-southeast-2.amazonaws.com/us.db
https://hive-in-the-cloud.s3.ap-southeast-2.amazonaws.com/asx.db
https://hive-in-the-cloud.s3.ap-southeast-2.amazonaws.com/nse.db
```

The bucket lives in `ap-southeast-2`. The regional host matters: the generic
`s3.amazonaws.com` host answers `301 PermanentRedirect` for it. The base URL
lives in `DbSyncService` and can be overridden at runtime.

### Schema

Each file holds one table per look-back window, plus `consistent_growth_stocks`.
The table *prefix differs between the files*, so nothing is hard-coded —
`MarketDatabase.open` reads `sqlite_master` and maps physical tables to windows
by suffix, and identifies the rest by their columns rather than their names.
That is what lets a new file be added by adding one value to the `Market` enum:

| File | Tables |
| --- | --- |
| `us.db` | `us_stocks_growth_{7_days,1_month,3_months,6_months,1_year}` |
| `asx.db` | `asx_etf_growth_{7_days,1_month,3_months,6_months,1_year}` |
| `nse.db` | `nse_stocks_growth_{...}`, whichever windows the run publishes |

Every growth table carries the same columns:

```
ticker, name, exchange, asset_type, first_date, first_price, last_date,
latest_price, pct_change, observations, days_covered, coverage,
observation_ratio, median_volume, price_basis, data_as_of, run_id,
google_finance
```

`asx.db` adds `issuer` and `category` after `asset_type` — who runs the fund
and what it holds (`crypto`, `precious metals`, `fixed income`). `us.db` and
`nse.db` publish neither, so the app discovers the columns at open time and
only offers the category and issuer filters where the file supports them.

`asx_universe` carries them too, which is what lets **Price history** filter
the whole market rather than only the tickers a screen picked up: 381 of the
456 tickers with published bars are labelled. The other 75 are not dropped —
a row the file publishes but leaves blank reads as **Misc**, and both filters
grow a `Misc` chip, last in the row, that selects exactly those. A file with
no such column at all shows no label and no chip.

Alongside those, each file publishes **weekly price history** in a table named
with the same prefix and no window suffix — `us_stocks_growth` and
`asx_etf_growth`:

```
stock_price_date, ticker, open, high, low, close, adj_close, volume,
growth_count, growth_periods
```

One year of Friday-aligned bars (2025-08-29 to 2026-08-21, up to 52 per
ticker), covering more tickers than the window tables do — 1,794 US and 56 ASX
at the time of writing. Every column is TEXT, prices included, so each numeric
field is parsed rather than cast. The table is found by its columns rather than
its name, and a file published before it existed still opens: `hasPriceHistory`
reports false and the charts fall back to the window endpoints.

Two further tables record how the run itself went, and are read the same way —
by their columns, so a file without them still opens:

```
run_metadata   run_id, code_revision, exchange, instrument_type, data_as_of,
               started_at, finished_at, status, universe_total,
               universe_screened, provider, source_run_id, source_status,
               settings_json
screen_funnel  window, position, stage, count
```

In Reports, every metadata value is set flush right and is never truncated: a
run id wraps onto a second line rather than ending in an ellipsis that cannot
be read or copied, and the app-wide selection area means any of it can be
selected. Both markets are rendered the same way — `us.db` publishes neither
table today, so its section says so, and it will show the same pair as ASX the
moment it does.

`run_metadata` holds a single row. `screen_funnel` holds one row per stage per
window — "Universe in window", "Enough span", "Enough observations", "Still
trading", "Adjusted prices", "Liquid enough", "Above price floor", "Valid
baseline", "Return above N%" — and its last count for a window equals that
window's published row count, so the funnel explains exactly why a window is
as small as it is (or, for ASX 3-month, empty). Reports shows both, per market,
and says so plainly where a file carries neither: `us.db` does not yet publish
them.

A window's table can be empty (ASX has no 3-month rows in the current run), and
`consistent_growth_stocks` may be absent or empty. Both cases are handled with
explanatory empty states rather than errors.

### What the data does *not* contain

- **Weekly bars, not daily.** The history is Friday-aligned, so the charts plot
  weekly closes at their own dates. A seven-day window therefore holds two of
  them; the desktop's security panel charts the full published year instead,
  which is the point of that panel.

### Two prices for the same window

The window tables and the weekly history disagree, and neither is wrong. A
window opens on a calendar date (MRNA's year starts 2025-08-25 at 25.10) while
the bars are Friday closes (the first is 2025-08-29 at 24.09), so the endpoints
— and the percentages derived from them — differ:

| Window | Screener | From weekly bars |
| --- | --- | --- |
| 7D | 63.89 → 139.23, +117.91% | 63.32 → 145.13, +129.20% |
| 1Y | 25.10 → 145.13, +478.21% | 24.09 → 145.13, +502.45% |

The detail screen shows the **weekly** figures, so its numbers match the line
above them, and prints the screener's own change directly beneath
("screener: +478.21%") with both sets listed and attributed under Detailed
Metrics. The lists and rankings keep the **screener's** figures — they are what
the pipeline screened and sorted on, and changing them there would make the app
disagree with its own source.
- **No index level.** There is no ASX or S&P value to show, so each market card
  leads with the *median percentage change* for the selected window over the
  instrument count. Its sparkline is a chain-linked index built from the weekly
  bars: the median week-over-week return, compounded. Normalising each ticker
  against its own first bar is the obvious alternative and is wrong here — the
  constituents enter the history at different dates, so that median lurches by
  tens of percent in a single week whenever the set changes. Chaining only ever
  compares a ticker with itself.

### Icon

`assets/icon/app_icon.png` and the Android launcher icons are generated by
`tool/make_icon.py` (Pillow) — a rising line over volume bars on a deep green
ground, in the app's own greens. The script writes every density, the adaptive
icon's foreground layer inside its 72dp safe zone, and the master used for the
Linux window icon; re-run it after changing the artwork.

### Motion

Transitions come from the `animations` package:

| Where | Transition |
| --- | --- |
| Any pushed route | Shared axis (horizontal) |
| A list row opening its stock | Container transform — the row grows into the screen |
| Desktop sidebar sections | Fade through |
| Stock detail's four tabs | Fade through |
| Info sheets | Fade + scale |

The handset's bottom navigation keeps its `IndexedStack`: swapping tabs with a
transition would discard each tab's scroll position and re-run its queries,
which costs more than the animation is worth.

### Selectable text

One `SelectionArea` wraps the whole navigator, so text on every screen — and in
every dialog — can be selected and copied. It sits inside an `Overlay` the
builder introduces, because `MaterialApp.builder` runs above the navigator that
would otherwise provide one. The price chart opts out with
`SelectionContainer.disabled`: it reads horizontal drags to move its cursor,
which is the same gesture text selection uses.

### A collapsible sidebar

The sidebar narrows to a 68px rail of icons — `Ctrl`/`Cmd`+`B`, or the control
at its foot — giving the content about 170px back. Collapsed, each destination
keeps its name in a tooltip, and the choice is remembered across restarts.

### Master and detail

Markets and Watchlist are two panes on a desktop window: the list on the left,
the instrument on the right. A row **selects** rather than navigates — the list
keeps its scroll position, its filters and its place, and the pane changes.
Pushing a screen for a row is what a handset does because it has nowhere else
to put it; a 1400px window does.

Both panes are framed and inset, so neither is pressed against the window edge,
and the desktop list is drawn as the table it is: headings on a tinted band,
a border, row separators, and the count in a footer strip (`TableFrame`). The
handset keeps its unframed full-width lists, where a border on every edge is
noise rather than structure.

### The detail screen on desktop

The stock detail is a one-column handset design reused on the desktop inside a
readable-width cap. Its bottom navigation bar, though, spanned the whole window
under a 900px column — a phone screen someone had stretched. On a desktop
window the four sections sit in the header toolbar beside the back button
instead; the handset keeps its bottom bar.

### Small screens

`test/small_screen_test.dart` walks the whole app — every tab, every sheet,
every list scrolled to its end — at seven configurations, from 320x640 to
640x320 landscape and up to 1.6x text. A layout overflow throws, so the
assertion is simply that the walk finishes without one.

What the rows do as space runs out, in order: the company name ellipsizes, the
market badge goes, then the price column goes (the change is what the list is
ranked on, and the price is one tap away). The sortable heading drops its Price
column in the same breath, so a heading never sits over the wrong values. The
price and change columns scale with the reader's text size rather than being
fixed in pixels — a fixed column ellipsizes its own numbers at 1.3x. Under
360dp the market list also shortens its tab labels and its title, since the
full ones are clipped rather than merely tight.

### Starring from a list

The star sits on the row, next to the Google Finance link — in the market
lists, the watchlist, search results, the dashboard's top gainers and the
desktop gainers table, as well as in the stock detail header. Tapping it toggles
the ticker in the watchlist and fills the icon; only the detail screen also
confirms with a snackbar, since a message per tap would stack up as you work
down a list.

Stars are stored per market (`us:MRNA`, not `MRNA`) in the app's own
preferences, never in the downloaded databases — those are read-only and are
replaced wholesale on every refresh. They survive a restart, a re-download and
a cache clear.

### Google Finance links

The `google_finance` column the pipeline publishes is reachable in one tap from
wherever a row is shown — every list row, every Top Gainers row, the stock
detail header, and the desktop dashboard's security panel. It used to live
behind the detail screen's overflow menu, which was four taps from a list; the
menu now offers to copy the link rather than open it.

### Info sheets

Every screen's app bar carries an info button. The sheets are written as data —
headings, paragraphs, bullets, worked examples, notes and dividers in
`lib/ui/info/page_info.dart` — and rendered by one widget, so they are spaced
and coloured identically and a change to the data model is described in one
place.

### Typography

The app is set in **Inter**, bundled at four weights (400/500/600/700) in
`assets/fonts` rather than fetched at runtime — it is offline-first, and the
type has to render identically with no connection. Inter is under the SIL Open
Font License; the licence travels with the files.

| UI element | Weight |
| --- | --- |
| Page title | 700 |
| Card title | 600 |
| Stock ticker | 700 |
| Company name | 400 |
| Large price | 600 |
| Percentage change | 600 |
| Table headers | 600 |
| Table values | 500 |
| Secondary metadata | 400 |

Widgets inherit the family through the theme. The chart painters name it
explicitly: a `TextPainter` has no widget ancestor to inherit from, so axis
labels and tooltips would otherwise fall back to the platform default.

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
- **No market-trend panel.** The mockup charts a market index below the table.
  That space instead charts the *security selected in the table* over its full
  published year, which is what the weekly history is for; clicking a row
  charts it in place, and "Open details" opens the full screen.
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

The same code runs as a Linux desktop app. The window opens at 1280x860, wide
enough for the sidebar layout; narrowing it below 900px switches to the handset
layout live.

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

133 tests cover the table discovery and every query (against fixture databases
built to the published schema, including the differing prefixes and the weekly
history), the run metadata and screen funnel (including the degraded path for
files without them), the price-series assembly and the chain-linked growth
curve, the sync
service (conditional requests, progress, corrupt downloads, failure handling),
the formatters and trend classifier, CSV rendering and the export's write path,
opening the published Google Finance links (including from a list row and
from the detail header, without a menu), starring from a list row and what
that leaves in the store, and both layouts driven end to end
against a fake S3 — including that a wide window gets the sidebar and a narrow
one does not, that the whole app lays out without overflow from 320dp to
landscape and at 1.6x text, that every screen carries an info button and its
sheet renders,
that the text sits inside the selection area, and that settings split into two
columns only when there is room.

Seven of those are the real-data tests below; they report as skipped unless
`SCREENER_DB_DIR` is set, so a plain `flutter test` shows `+82 ~7`.

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
