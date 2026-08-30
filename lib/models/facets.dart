/// The label a row carries when the file publishes the column but left the
/// value blank — 75 of the 457 ASX tickers have no category, and one has no
/// issuer.
///
/// It doubles as the value a filter carries for those rows, so selecting the
/// "Misc" chip keeps exactly the rows nothing else claims rather than dropping
/// them. A file that publishes no such column at all reports null instead, and
/// gets no chip.
///
/// If a file ever publishes a category genuinely spelled "Misc", it and the
/// blanks merge under one chip. That is the right outcome for a reader and
/// costs nothing to allow.
const String kMiscLabel = 'Misc';
