# Screener workspace design

The design applies to the entire Flutter app, using `AppTheme` and the shared
surface, table, list, badge and dialog components. The HTML files in
`design-mockups/` are design references; the shipped UI uses Flutter widgets.

## Visual rules

- Roboto Condensed typography (the mockups' face), drawn 15% over nominal
  size (`kTypeScale`) because the sizes were set for the wider Inter; slate page backgrounds, opaque cards and teal navigation.
- Rounded 12 dp panels and 8 dp controls, with subtle 1 dp dividers.
- Green and red indicate movement; teal (`ScreenerColors.interactive`)
  indicates selection and actions.
- Semantic badges use tinted fills and readable foregrounds in both themes.
- Security monograms are neutral so they do not compete with price changes.
- Keyboard focus, ink feedback, selected states, compact rows, text scaling and
  reduced-motion preferences remain available.

## Review status

Pages are being matched to `design-mockups/equivalent-screens.html` one at a
time, each signed off against a render before the next starts.

| Page | Status |
| --- | --- |
| Settings | Rebuilt to the mockup: compact title bar, checkboxes, inline theme pills, actions inside the data-source card |
| Dashboard | Security/name column, compact heading, stacked movers and consistent phone gainers; rendered for review, awaiting acceptance |
| Stock overview, Performance, Metrics | Restyled, not yet reviewed against the mockup |
| Everything else | Restyled only |

## Screen coverage

| Area | Views covered |
| --- | --- |
| Shell | Expanded and collapsed desktop navigation, mobile bottom navigation, split list/detail panes |
| Dashboard | Desktop gainers table, selected security chart, analyses and movers; mobile market/window controls, leader, runners-up and watchlist snapshot |
| Markets | All stocks, top movers, consistent growers and starred stocks; sorting, category facets, market/window selection |
| Stock details | Overview, weekly chart and periods, screen explanation, provenance, external links, performance and coverage, key metrics |
| Detailed metrics | Responsive groups for security identity, screener endpoints, weekly observations and data quality; all published fields retained |
| Price history | Whole-market ticker list, search/filter controls, selected ticker chart and range metrics |
| Search | Current-screen, historical and starred matches; empty and no-result states |
| Watchlist | Listed and dropped tickers, selected detail pane, removal and undo |
| Reports | Published runs, CSV exports, run metadata and screening funnels |
| Settings | Data sources/cache, appearance, watchlist management, reports, digest delivery/markets/thresholds, activity and About |
| Supporting UI | Help sheets, confirmation dialogs, filter sheets, loading/error/empty states, banners and snackbars |

Desktop settings keep general controls in one column and the digest in the other;
phones stack the same sections. Detailed metrics use two columns when the actual
pane is at least 640 dp wide and stack below that width. Existing market data,
calculations, caching, exports, external links and notification behavior are
unchanged.

## Validation

Use `flutter analyze`, `flutter test`, and `flutter build linux --debug`.
The test suite includes navigation, filtering, history, watchlist, exports,
digests, desktop layouts, narrow screens with larger text, contrast and reduced
motion. Real-database tests need `SCREENER_DB_DIR`; fixture tests work offline.
