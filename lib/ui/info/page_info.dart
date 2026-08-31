import 'package:flutter/material.dart';

import '../widgets/info_dialog.dart';

/// What each screen's info button explains.
///
/// Kept together so the explanations stay consistent with one another, and so
/// a change in the data model is described in one place rather than five.
class PageInfos {
  const PageInfos._();

  /// Repeated wherever a screen shows a percentage change, because it is the
  /// single most misread number in the app.
  static const _screenerNumbers = InfoNote(
    'Every figure here is screener output, not a live quote. A change is '
    'measured between two published endpoints, not since this morning.',
  );

  static const dashboard = PageInfo(
    title: 'Dashboard',
    subtitle: 'What the app found in the latest run',
    icon: Icons.dashboard_outlined,
    blocks: [
      InfoParagraph(
        'The dashboard is a summary of the two screener databases the app '
        'downloads from S3 — one for the ASX, one for the US market. Nothing '
        'here is computed from live prices; it is all read from the files.',
      ),
      InfoHeading('Market cards', icon: Icons.credit_card_outlined),
      InfoParagraph(
        'One card per market. The big figure is the median percentage change '
        'across every instrument that passed the screen for the selected '
        'window, so a single runaway ticker cannot drag it.',
      ),
      InfoBullets([
        InfoBullet(
          lead: 'Median, not average',
          text: 'half the instruments did better, half did worse.',
        ),
        InfoBullet(
          lead: 'The sparkline',
          text:
              'traces the market’s weekly path over the published year, '
              'chained from median weekly returns.',
        ),
        InfoBullet(
          lead: 'The caption',
          text: 'names the window and how many instruments it covers.',
        ),
      ]),
      InfoDivider(),
      InfoHeading('Top Gainers', icon: Icons.trending_up),
      InfoParagraph(
        'The strongest instruments in the selected window, sorted by '
        'percentage change. Tap a row to open its detail screen.',
      ),
      InfoExample(
        title: 'Reading a row',
        lines: [
          'MRNA · Moderna, Inc. · US',
          '139.22   +75.33   +117.9%',
          'Last price, change since the window opened, and that change as a '
              'percentage.',
        ],
      ),
      InfoHeading('Analysis Summary', icon: Icons.insights_outlined),
      InfoParagraph(
        'Totals for the latest run: how many window analyses were published, '
        'how many rows they hold in total, and the average change across the '
        'selected window.',
      ),
      InfoNote(
        'Rows counts a ticker once per window it appears in, so a ticker in '
        'five windows contributes five rows. Each file carries a single run, '
        'so there is no earlier run to compare against and no month-on-month '
        'delta to show.',
      ),
      _screenerNumbers,
    ],
  );

  static const markets = PageInfo(
    title: 'Markets',
    subtitle: 'Every instrument that passed the screen',
    icon: Icons.public,
    blocks: [
      InfoParagraph(
        'The full list for one market and one look-back window, with the '
        'columns the screener published. Switch market from the title, and '
        'window from the selector below it.',
      ),
      InfoHeading('The four tabs', icon: Icons.tab_outlined),
      InfoBullets([
        InfoBullet(
          lead: 'All Stocks',
          text: 'everything published for the selected window.',
        ),
        InfoBullet(
          lead: 'Top Movers',
          text: 'the strongest performers in that window, largest first.',
        ),
        InfoBullet(
          lead: 'Consistent',
          text:
              'instruments that cleared the threshold in every window, not '
              'just one. Published as its own table, and absent from some '
              'files.',
        ),
        InfoBullet(
          lead: 'Watchlist',
          text: 'the tickers you have starred, across every market.',
        ),
      ]),
      InfoDivider(),
      InfoHeading('Why a ticker is here', icon: Icons.rule),
      InfoParagraph(
        'Each window screens on a minimum change — the cut-off the run '
        'applied, named beside the row count at the foot of the list. Every '
        'row in the list reached it; nothing that fell short was published. '
        'The longer windows screen harder: 10% over a week or a month, 25% '
        'over a quarter or more.',
      ),
      InfoDivider(),
      InfoHeading('Sorting and filtering', icon: Icons.filter_alt_outlined),
      InfoParagraph(
        'Tap a column heading to sort by it; tap again to reverse. The filter '
        'button narrows the list by exchange and by a minimum percentage '
        'change, and search matches both ticker and company name.',
      ),
      InfoExample(
        title: 'Finding solid movers, not spikes',
        lines: [
          '1. Set the window to 1M.',
          '2. Filter to a minimum change of 25%.',
          '3. Sort by Median Vol. to put the liquid names first.',
        ],
      ),
      _screenerNumbers,
    ],
  );

  static const stockDetail = PageInfo(
    title: 'Stock detail',
    subtitle: 'One instrument, in full',
    icon: Icons.show_chart,
    blocks: [
      InfoParagraph(
        'Everything the databases hold about one instrument: its price path, '
        'the screener’s metrics, how it performed across every window, '
        'and the links published with it.',
      ),
      InfoHeading('The chart', icon: Icons.timeline),
      InfoParagraph(
        'Weekly closing prices, plotted at their real dates — a gap in the '
        'series shows as a longer segment rather than being spaced evenly. '
        'Tap or drag across it to read any point.',
      ),
      InfoHeading('Why it is listed', icon: Icons.rule),
      InfoParagraph(
        'Under the price is the rule this instrument satisfied: the window’s '
        'cut-off, and how far past it the published change landed. Switch '
        'window with the pills and the rule changes with it — the screen is '
        'stricter over longer periods.',
      ),
      InfoHeading('Two changes, both correct', icon: Icons.compare_arrows),
      InfoParagraph(
        'The change under the price is measured between the first and last '
        'weekly bars in the window. The screener measures its own change '
        'between the window’s true endpoints, which the weekly sampling '
        'does not necessarily contain — so the two differ, and both are shown '
        'rather than one being quietly preferred.',
      ),
      InfoExample(
        title: 'A 7-day window',
        lines: [
          'Weekly bars:  Aug 14 → Aug 21   +78.7%',
          'Screener:     its own endpoints  +81.9%',
          'The gap is the sampling, not an error in either figure.',
        ],
      ),
      InfoDivider(),
      InfoHeading('The tabs', icon: Icons.view_agenda_outlined),
      InfoBullets([
        InfoBullet(
          lead: 'Overview',
          text:
              'the chart, the window selector, the headline metrics, and the '
              'run and Google Finance link the figures came from.',
        ),
        InfoBullet(
          lead: 'Performance',
          text:
              'the same instrument across 7D to 1Y, so a spike and a trend '
              'are easy to tell apart.',
        ),
        InfoBullet(
          lead: 'Metrics',
          text:
              'every published column — coverage, observations, median volume '
              'and price basis.',
        ),
      ]),
      InfoHeading('Coverage and observations', icon: Icons.rule),
      InfoBullets([
        InfoBullet(
          lead: 'Coverage',
          text:
              'how much of the window the data actually spans, 0 to 1. Below '
              '1 means the instrument was not trading for the whole period.',
        ),
        InfoBullet(
          lead: 'Obs. ratio',
          text:
              'observed trading days against expected. A low ratio means a '
              'thin, gappy series.',
        ),
        InfoBullet(
          lead: 'Price basis',
          text:
              '"adjusted" means splits and dividends are already accounted '
              'for in the prices.',
        ),
      ]),
      _screenerNumbers,
    ],
  );

  static const watchlist = PageInfo(
    title: 'Watchlist',
    subtitle: 'The tickers you starred',
    icon: Icons.star_border_rounded,
    blocks: [
      InfoParagraph(
        'Instruments you have starred, from every market in one list. Star '
        'from any list row or from the detail screen’s header.',
      ),
      InfoBullets([
        InfoBullet(text: 'Swipe a row to remove it.'),
        InfoBullet(text: 'Tap a row to open its detail screen.'),
        InfoBullet(
          text:
              'A starred ticker is tinted wherever it is listed — every '
              'window, the consistent growers, the price history — so you '
              'can pick it out while scanning.',
        ),
        InfoBullet(
          text:
              'A star stays until you take it off. Nothing a run publishes '
              'removes one.',
        ),
        InfoBullet(
          text:
              'The list is stored on this device only — it is not part of '
              'the published data and is not synced anywhere.',
        ),
      ], icon: Icons.check_circle_outline),
      InfoNote(
        'A starred ticker only appears here while it is still in the '
        'published data. If the next run drops it from every window, the row '
        'goes with it.',
      ),
    ],
  );

  static const reports = PageInfo(
    title: 'Reports',
    subtitle: 'Where the numbers came from',
    icon: Icons.description_outlined,
    blocks: [
      InfoParagraph(
        'The provenance of the data: which runs produced the files, how many '
        'rows each window holds, what the run was configured to do, and where '
        'the instruments dropped out of the screen.',
      ),
      InfoHeading('Run inventory', icon: Icons.list_alt),
      InfoParagraph(
        'One line per window with its row count, the date the data was current '
        'as of, and the run id. The CSV button exports that window exactly as '
        'published — every column, unchanged.',
      ),
      InfoHeading('Run metadata', icon: Icons.badge_outlined),
      InfoParagraph(
        'A single row describing the run itself: the universe it started from, '
        'how many instruments it screened, when it ran and for how long, the '
        'price provider, the code revision, and the thresholds it applied.',
      ),
      InfoDivider(),
      InfoHeading('Screen funnel', icon: Icons.filter_alt_outlined),
      InfoParagraph(
        'How many instruments survived each stage of the screen, for the '
        'selected window. Read top to bottom: each bar is a share of the '
        'starting universe, and the red figure is what the stage removed.',
      ),
      InfoExample(
        title: 'An ASX 7-day funnel',
        lines: [
          'Universe in window   402',
          'Liquid enough        339   −63',
          'Above price floor    319   −20',
          'Return above 10.0%     6   −313',
          'The last count is exactly what the window publishes.',
        ],
      ),
      InfoParagraph(
        'That final line is why a window can look empty: it is not missing '
        'data, it is a threshold nothing cleared.',
      ),
      InfoNote(
        'Older files carry no run metadata or funnel. Where a market publishes '
        'neither, the page says so rather than leaving a gap.',
      ),
    ],
  );

  static const history = PageInfo(
    title: 'Price history',
    subtitle: 'Every ticker the run collected',
    icon: Icons.candlestick_chart_outlined,
    blocks: [
      InfoParagraph(
        'The growth tables only carry what passed a screen. This page reads '
        'the whole-market history table published alongside them, so a ticker '
        'that never moved enough to be screened can still be looked up and '
        'charted.',
      ),
      InfoHeading('Reading the list', icon: Icons.list_alt_outlined),
      InfoBullets([
        InfoBullet(
          lead: 'The change',
          text:
              'is measured across the whole published history, first bar to '
              'last — not the screener windows, which cover fixed periods.',
        ),
        InfoBullet(
          lead: 'Names',
          text:
              'come from the file\u2019s ticker directory when it publishes '
              'one, and from the growth tables otherwise — in which case a '
              'ticker no screen picked up shows its bar count instead.',
        ),
        InfoBullet(
          lead: 'The order',
          text:
              'is strongest first, as the file publishes it. Search by code '
              'or name when you are looking for one ticker in particular.',
        ),
      ]),
      InfoHeading('The chart', icon: Icons.show_chart),
      InfoParagraph(
        'Published closes at their real dates, adjusted where the file '
        'publishes an adjusted price. The period buttons trim the range from '
        'the last bar backwards; "All" shows everything the file holds.',
      ),
      _screenerNumbers,
    ],
  );

  static const settings = PageInfo(
    title: 'Settings',
    subtitle: 'Data sources, cache and appearance',
    icon: Icons.settings_outlined,
    blocks: [
      InfoHeading('Data sources', icon: Icons.cloud_download_outlined),
      InfoParagraph(
        'The app reads two SQLite files published to S3 and keeps a copy on '
        'this device. Each row shows the file’s state, its size, and when '
        'it was last synced.',
      ),
      InfoBullets([
        InfoBullet(
          lead: 'Re-download',
          text:
              'fetches every file unconditionally. A normal refresh sends the '
              'stored ETag and skips the download when nothing has changed.',
        ),
        InfoBullet(
          lead: 'Clear cache',
          text:
              'deletes the local copies. The app has nothing to show until '
              'the next download completes.',
        ),
      ]),
      InfoNote(
        'Everything except the refresh works offline. A failed refresh keeps '
        'serving the cached files rather than emptying the screens.',
      ),
      InfoDivider(),
      InfoHeading('Refresh and alerts', icon: Icons.notifications_none),
      InfoParagraph(
        'Every file is fetched at 9:00 and again at 11:00, and each one that '
        'actually changed is announced. Then the 7-day screen is compared '
        'with the last time it was checked: every ticker that joined gets a '
        'notification of its own, naming the company and its move.',
      ),
      InfoBullets([
        InfoBullet(
          lead: 'Only what is new',
          text:
              'a ticker already in the screen is never announced twice, so '
              'the second run of the day is usually silent.',
        ),
        InfoBullet(
          lead: 'On Android',
          text:
              'the app is woken to do the work, so the alerts arrive whether '
              'or not it is open. The system may hold a wake-up back a few '
              'minutes to batch work.',
        ),
        InfoBullet(
          lead: 'On desktop',
          text:
              'nothing wakes the app on a schedule, so the check runs the '
              'next time it is opened.',
        ),
        InfoBullet(
          lead: 'Check now',
          text: 'fetches every file and posts what is in the screen today.',
        ),
      ]),
      InfoDivider(),
      InfoHeading('Appearance', icon: Icons.palette_outlined),
      InfoBullets([
        InfoBullet(
          lead: 'Theme',
          text: 'light, dark, or follow the system setting.',
        ),
        InfoBullet(
          lead: 'Compact rows',
          text: 'tightens list rows to fit more instruments on screen.',
        ),
      ]),
      InfoHeading('Reports and watchlist', icon: Icons.description_outlined),
      InfoParagraph(
        'Reports opens the run inventory, run metadata and screen funnel, and '
        'exports any window as CSV. The watchlist row shows how many tickers '
        'are starred in each market and can clear them all.',
      ),
    ],
  );

  static const search = PageInfo(
    title: 'Search',
    subtitle: 'Find an instrument in any market',
    icon: Icons.search,
    blocks: [
      InfoParagraph(
        'Searches every database at once, matching on ticker and on company '
        'name, and groups the results by where the match was found.',
      ),
      InfoBullets([
        InfoBullet(
          lead: 'In the screen',
          text:
              'published by this run for the selected window, with its '
              'figures.',
        ),
        InfoBullet(
          lead: 'In market history',
          text:
              'the file publishes prices for it, but this window screened it '
              'out. Each result names the window it did clear, if any.',
        ),
        InfoBullet(
          lead: 'Watchlisted',
          text:
              'starred, and the latest run says nothing about it at all — no '
              'screen row and no prices.',
        ),
      ], icon: Icons.check_circle_outline),
      InfoNote(
        'A ticker appears in one group only, the first it qualifies for, so '
        'nothing is listed twice.',
      ),
    ],
  );
}
