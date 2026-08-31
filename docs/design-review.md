# Screener Design Review

**Repository:** `ryandam9/Screener`  
**Reviewed branch:** `main`  
**Reviewed commit:** `0664cd23239ae8a2ad39ac8a9d70eb5aebacde8a`  
**Review date:** 31 August 2026

## Purpose

This document reviews the visual design, information hierarchy, responsive behaviour, interaction design, accessibility and overall product experience of the Screener Flutter application.

This is intentionally a **design review**. It does not cover database implementation, application architecture, background processing or other engineering concerns except where the current implementation directly constrains the user experience.

## Executive summary

Screener already has a strong design foundation. It behaves like a real desktop application at wide widths, adapts carefully to small phones, uses appropriate financial terminology, bundles a suitable typeface and contains many thoughtful interaction details.

The main opportunity is not a complete visual overhaul. The application needs a clearer hierarchy and a more focused visual language. At present, many cards, panels, controls and data sections receive similar visual weight. This can make the interface feel like a general administration dashboard instead of a purpose-built stock screener.

The highest-value design improvements are:

1. Separate the interactive accent colour from financial gain/loss colours.
2. Make the results table or mover list the dominant element of each analysis screen.
3. Reduce the number of bordered cards and nested panels.
4. Introduce a compact/tablet layout between handset and full desktop.
5. Simplify the Stock Detail information architecture.
6. Keep watchlisted instruments visible even when they leave the selected screen.
7. Improve small-text contrast, touch-target sizes and chart accessibility.

## What is working well

### Responsive intent

The application does not merely stretch a phone interface across a desktop window. The sidebar, master/detail views, keyboard shortcuts, readable-width constraints and desktop dashboard are all appropriate desktop patterns.

### Financial context

The interface distinguishes screener output from live market quotes, shows publication dates, handles currencies by market and avoids presenting calculated substitutes as official index values. This builds trust.

### Typography

Inter is a good choice for a dense financial application. It is neutral, compact and highly legible. Bundling regular, medium, semibold and bold weights gives the interface enough hierarchy without relying on excessive size changes.

### Useful interaction details

- Watchlist actions are available directly from lists.
- External quote links are not buried inside multiple menus.
- Desktop navigation can collapse to an icon rail.
- Master/detail layouts preserve the user's list position.
- Small-screen layouts deliberately remove lower-priority columns before essential information.
- Empty states explain why data is unavailable rather than showing an empty surface.
- Tabular figures are used for financial values.

These behaviours should be retained during redesign.

## Design principles for the next iteration

### 1. Analysis before decoration

The primary data should occupy the largest and most visually prominent area. Supporting information should be quieter and progressively disclosed.

### 2. One colour, one meaning

Navigation selection, positive price movement, warnings and destructive actions should not share semantic colours.

### 3. Fewer containers, stronger grouping

Use spacing, typography, alignment and subtle dividers before adding another bordered card.

### 4. Preserve scanning speed

Rows, numbers and sort controls should remain stable while filtering or changing markets. Decorative elements should never move financial columns out of alignment.

### 5. Design for three widths

Handset, compact/tablet and full desktop require different navigation and detail behaviour. A single breakpoint cannot serve all three comfortably.

## Visual language

### Colour semantics

The current primary green is also the positive-performance colour. This creates ambiguity: a green navigation item can read as a gain, while a green focus ring can look like a positive status.

Recommended roles:

| Role | Recommended use |
| --- | --- |
| Interactive accent | Navigation, focus, selected tabs, links and primary actions. Use blue or blue-teal. |
| Positive | Gains and successful market outcomes only. |
| Negative | Losses, destructive actions and genuine errors. Do not use it for neutral empty states. |
| Warning | Stale data, cached data and delayed publication. |
| Neutral | Secondary controls, metadata and inactive navigation. |

Suggested starting palette for the light theme:

| Token | Suggested colour | Purpose |
| --- | --- | --- |
| Interactive | `#2563EB` | Navigation, selected controls and focus |
| Positive | `#00875A` | Positive price movement |
| Negative | `#C62828` | Negative price movement and destructive actions |
| Warning | `#96660C` | Stale or cached data |
| Page | `#F5F7F9` | Application background |
| Surface | `#FFFFFF` | Main content surfaces |
| Primary text | `#171A21` | Titles and important values |
| Secondary text | `#596371` | Supporting text |
| Tertiary text | `#6B7280` | Small metadata and chart labels |

The exact palette should be validated in both themes, but the semantic separation is more important than the precise hue.

### Contrast

The light-theme tertiary colour `#8C95A1` has approximately:

- `3.03:1` contrast on white.
- `2.80:1` contrast on the page background.

It is used for small labels and metadata, where that contrast is insufficient. Darken tertiary text and avoid placing essential information below 12 logical pixels.

### Containers and elevation

The interface uses rounded, bordered cards for many sections. When every section is a card, cards stop communicating importance.

Use cards for:

- A selected instrument summary.
- A market-level summary.
- An alert or data-quality warning.
- A short, self-contained KPI group.

Prefer flat sections for:

- Tables and long lists.
- Filter controls.
- Run metadata.
- Settings groups.
- Secondary dashboard panels.

Recommended surface treatment:

- 10–12px radius for major cards.
- 8px radius for controls.
- Subtle borders only where the edge is otherwise unclear.
- No nested bordered card inside another bordered card.
- Use 16–24px section spacing instead of additional containers.

### Typography hierarchy

Retain Inter and the existing tabular-number treatment.

| Role | Mobile | Desktop | Weight |
| --- | --- | --- | --- |
| Page title | 20/28 | 24/32 | 700 |
| Section title | 16/24 | 17/24 | 600 |
| Primary value | 24/30 | 28/34 | 600–700 |
| Ticker | 14/20 | 14/20 | 700 |
| Company name | 13/19 | 13/19 | 400–500 |
| Body | 14/20 | 14/20 | 400 |
| Metadata | 12/16 | 12/16 | 400–500 |

Avoid relying on 10–11px grey text for information a user may need to make a decision.

### Motion

The current transition choices are coherent, but some durations are long for a data-scanning application.

- Use approximately 180–220ms for section and tab changes.
- Use approximately 220–260ms for opening a detail view.
- Respect the platform's reduced-motion setting.
- Avoid animating frequently changing numerical values unless the animation communicates the change.

## Responsive strategy

The current design switches directly between handset and desktop at 900 logical pixels. A full sidebar and master/detail content can become cramped just above that boundary.

Recommended model:

| Available width | Navigation | Content behaviour |
| --- | --- | --- |
| `< 720px` | Bottom navigation | Single pane; detail opens as a page |
| `720–1099px` | Compact navigation rail | Single pane or overlay detail; denser tables where appropriate |
| `>= 1100px` | Full or collapsible sidebar | Full master/detail and multi-column dashboard |

At compact widths, do not force a 380px list beside a narrow detail pane. Prefer a single pane with a clear back action, or temporarily expand the selected item into the content area.

## Screen-by-screen review

### Desktop dashboard

#### Current strengths

- The desktop has a dedicated dashboard instead of reusing the handset composition.
- The selected instrument and chart create useful context for the gainers table.
- Recent analyses and movers give the page depth.

#### Concerns

- Summary cards, the gainers table, chart and supporting panels compete for attention.
- Four equally weighted KPI cards can dominate the first viewport even though the table is the core working area.
- Market, analysis-window and freshness controls are distributed instead of forming one clear context bar.

#### Recommended structure

1. **Context header**
   - Page title.
   - Market scope.
   - Analysis window.
   - Published/synchronised status.
   - Search.

2. **Compact KPI strip**
   - Instruments in screen.
   - Median change.
   - Strongest move.
   - New entrants, if available.

3. **Primary workspace**
   - Left 60–65%: Top Movers table.
   - Right 35–40%: selected instrument, price movement and chart.

4. **Secondary information**
   - Recent analyses.
   - Market breakdown or other supporting statistics.

The table should be visible without scrolling at a typical 1280×800 desktop size.

#### Recommended changes

- Reduce the height and visual weight of KPI cards.
- Put the selected analysis window in the page header rather than hiding it among local controls.
- Use one main white workspace surface for table and chart, separated by a divider.
- Keep supporting panels below the primary workspace.
- Make the selected table row visually clear without using the financial positive colour.

### Mobile dashboard

#### Concerns

Showing multiple tall market cards before the main results can make the page long and delay access to the content users open the app to see.

#### Recommended order

1. Freshness/status line.
2. Market segmented control: ASX / US / NSE.
3. Analysis-window selector.
4. One compact market summary.
5. Top Movers.
6. Watchlist snapshot.
7. Recent analysis runs.

Use a selected market rather than three full-height market summaries. A compact comparison strip can remain available when cross-market comparison is useful.

### Markets

#### Current strengths

- All Stocks, Movers, Consistent and Watchlist are meaningful views.
- Sort headings remain aligned with financial values.
- Lower-priority information is removed progressively on narrow screens.

#### Recommended changes

- Keep search persistent on desktop rather than toggling it into the title area.
- Use a compact context toolbar containing market, window and filter count.
- Keep the column header sticky while scrolling long lists.
- Present active filters as removable chips directly above the results.
- Place “Clear all” beside the active filters, not only inside the filter sheet.
- Preserve the user's sort and filter state per market during the session.
- Debounce the mobile list search so every keystroke does not appear to refresh the entire screen.

### Stock detail

#### Current strengths

- The screen distinguishes weekly-chart figures from screener endpoint figures.
- The header exposes watchlist and external actions.
- Multiple analysis windows can be compared.

#### Concerns

- Overview, Metrics, Windows and Links divide the information too finely.
- A dedicated Links tab adds navigation without adding enough content.
- The most important question—why this ticker passed the screen—can be lost among detailed fields.

#### Recommended information architecture

**Header**

- Ticker and company name.
- Market/exchange.
- Current published endpoint price.
- Signed change and selected window.
- Star and Google Finance actions.
- Data-as-of date.

**Tabs**

1. **Overview** — chart, price endpoints and a plain-language “Why it passed” summary.
2. **Performance** — window comparison and historical movement.
3. **Metrics** — volume, observations, coverage and full published fields.

Move secondary links into the header overflow or a compact “External links” row at the bottom of Overview.

### Watchlist

The watchlist should behave like a persistent collection, not another filtered screen.

Currently, a starred ticker can disappear from the list when it is absent from the selected window. Although the interface reports a missing count, disappearance makes the watchlist less dependable.

Recommended behaviour:

- Always display every starred ticker.
- Use the most recent history value where a current screen row is unavailable.
- Add a status such as “Not in the 7-day screen” or “Dropped from latest run.”
- Allow grouping by market.
- Add sorting by name, latest movement and watchlist status.
- Keep swipe-to-remove, with an Undo snackbar.

### Global search

Search currently reflects instruments available in the selected screener window. Users may reasonably expect global search to find any instrument available in price history.

Recommended result groups:

- **In current screen**
- **Available in market history**
- **Watchlisted**

Each result should state why it appears and whether it currently passes the selected screen.

### Price history

- Make the selected instrument row more prominent in the split view.
- Keep the time-range control close to the chart rather than in the list header.
- Add a short chart summary for accessibility and quick reading: start, end, high, low and percentage movement.
- On desktop, support left/right arrow keys for moving the selected chart point.
- On mobile, retain drag exploration but also allow tapping a point to keep its tooltip visible.

### Reports

Reports contain valuable provenance but can become visually technical.

Recommended structure:

- Group by market.
- Lead with run date, data-as-of, status and number of screened instruments.
- Place run ID, code revision, source run and settings JSON inside an expandable “Technical details” section.
- Show the screen funnel as a compact vertical sequence or decreasing bars rather than a long metadata list.
- Keep CSV export beside the relevant run/window.

### Settings and More

Use three primary groups:

1. **Data & Sync**
   - File status.
   - Last publication and sync.
   - Refresh action.
   - Cache size.

2. **Appearance**
   - Theme.
   - Row density.
   - Desktop sidebar preference where applicable.

3. **Alerts**
   - Enable alerts.
   - Schedule explanation.
   - Check now.
   - Last alert.

Place base URL editing, cache deletion and diagnostic metadata behind an **Advanced** disclosure. These controls should not compete with everyday settings.

## Navigation review

### Mobile

The four destinations—Dashboard, Markets, Watchlist and More—are appropriate. Keep them stable.

History and Reports can remain inside More unless user behaviour shows that one is frequently used. Avoid expanding the bottom navigation beyond five items.

### Desktop

The sidebar destinations are appropriate and the collapse affordance is useful.

Recommended refinements:

- Reduce the expanded width slightly, from 236px toward 216–224px.
- Use the interactive accent colour for selection rather than positive green.
- Retain the 68px collapsed rail.
- Keep labels visible at compact/tablet widths only when space permits.
- Add a stronger section title in the content header so the page does not rely only on the selected sidebar item.

## Tables and lists

The screener table is the product's central working surface.

Recommended table behaviour:

- Sticky column header.
- Clearly visible current sort and direction.
- Stable numeric column widths.
- Right-aligned numerical values.
- Tabular figures throughout.
- Row hover state on desktop.
- Keyboard focus state distinct from selected-stock state.
- Selected row uses a neutral or interactive tint, not gain green.
- Watchlisted row uses a subtle star indicator; avoid tinting the entire row strongly enough to compete with selection.
- Optional density control can remain, but compact mode must preserve usable action targets.

Avoid putting both star and external-link actions into 26×26px interactive regions. Keep the icons compact while providing at least a 44–48px hit area on touch devices.

## Charts

The custom price chart is visually appropriate for the app, but chart comprehension should not depend on pointer exploration.

Recommended additions:

- Visible time-range selection near the chart.
- Start/end values and signed change above the chart.
- Accessible text summary.
- Keyboard point navigation on desktop.
- Persistent selected tooltip after a tap.
- Clear indication that points are weekly, not daily.
- Optional high/low labels when they do not clutter the chart.

Keep chart gridlines subdued and ensure axis labels meet contrast requirements.

## Accessibility

### Touch targets

Interactive controls should provide a minimum 44–48px target on touch devices. This particularly affects the dense star and external-link controls.

### Keyboard

The desktop application should support:

- Tab navigation through rows and controls.
- Enter/Space to open or select a row.
- Arrow keys for chart exploration where the chart has focus.
- A visible focus ring that is different from both row selection and positive performance.

### Screen readers

Provide semantic summaries for:

- Price charts.
- Sparklines.
- Change chips.
- Ticker avatars.
- Selected rows.
- Sync and stale-data indicators.

A chart summary should include ticker, period, start value, end value and signed change.

### Text scaling

Continue testing narrow screens with enlarged text, but extend coverage beyond 1.6× where practical. Essential values should wrap or reflow rather than disappear solely because the user selected a larger text size.

### Colour independence

Positive and negative movement already includes signed text, which is good. Retain signs, labels or arrows so colour is never the only signal.

## Content and terminology

- Prefer **Last published** for the pipeline timestamp and **Downloaded** for the device timestamp. Do not merge them into a generic “Updated.”
- Use **Screen** for a filtered set of instruments and **Market history** for the wider universe.
- Keep “Not live quotes” near the first price-heavy view, then place the longer disclaimer in About/Info.
- Prefer plain-language explanations before technical field names.
- Use sentence case consistently for section titles and controls.

## Prioritised implementation plan

### Phase 1 — Foundation

| Priority | Change | Expected outcome |
| --- | --- | --- |
| P0 | Separate interactive accent from positive green | Clearer financial semantics |
| P0 | Darken tertiary text and chart labels | Improved readability and accessibility |
| P0 | Increase dense action hit areas | Fewer missed taps |
| P1 | Introduce compact/tablet breakpoint | Prevent cramped desktop layouts |
| P1 | Reduce transition durations | Faster perceived performance |

### Phase 2 — Primary workflows

| Priority | Change | Expected outcome |
| --- | --- | --- |
| P1 | Restructure desktop dashboard around table + selected instrument | Stronger hierarchy and faster scanning |
| P1 | Simplify mobile dashboard | Quicker access to movers |
| P1 | Simplify Stock Detail to three sections | Reduced navigation overhead |
| P1 | Keep all watchlisted instruments visible | More dependable watchlist |
| P2 | Group global search results by availability | Search matches user expectations |

### Phase 3 — Supporting screens

| Priority | Change | Expected outcome |
| --- | --- | --- |
| P2 | Simplify Reports and collapse technical metadata | Easier provenance review |
| P2 | Reorganise Settings into three groups | Less visual and conceptual clutter |
| P2 | Add chart keyboard and semantic support | Better desktop and assistive use |
| P3 | Add saved filter presets | Faster repeated analysis |

## Suggested redesign order

Redesign and validate one workflow at a time:

1. Desktop Dashboard.
2. Mobile Dashboard.
3. Markets list and filters.
4. Stock Detail.
5. Watchlist.
6. Reports and History.
7. Settings and final design-system consolidation.

Starting with the desktop dashboard establishes the colour, spacing, card, table, header and typography decisions that every other screen can reuse.

## Acceptance criteria for the redesign

The design iteration should be considered successful when:

- The primary analysis table or list is visible without unnecessary scrolling.
- Interactive selection cannot be confused with positive performance.
- A 900–1099px window does not force an unusably narrow master/detail layout.
- Every essential touch action has a comfortable hit area.
- Small metadata and chart labels meet contrast requirements.
- The Stock Detail screen answers “What moved?”, “Why did it pass?” and “What happened over time?” without requiring four separate tabs.
- Every starred ticker remains visible in the watchlist.
- The first viewport on mobile reaches useful market results quickly.
- The desktop interface remains efficient with keyboard-only navigation.

## Final assessment

Screener does not need a new personality. It already has an appropriate typeface, restrained surfaces, useful responsive behaviours and strong financial context. The next design iteration should concentrate on **focus**: fewer equally weighted containers, clearer colour semantics, a stronger primary workspace and progressive disclosure of technical detail.

The desktop dashboard should be the first redesign target because it contains nearly every important pattern—navigation, context controls, KPIs, tables, charts, selected state and supporting information. Once that screen is resolved, the resulting design system can be applied consistently across the rest of the application.
