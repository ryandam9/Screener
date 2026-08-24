import 'package:flutter/foundation.dart';

/// A request from outside the widget tree to show the 7-day list.
///
/// Tapping the morning digest should land on what the digest is about. Both
/// shells own their own selected section, so the request is raised here and
/// each shell consumes it the next time it builds.
class DigestRouter extends ChangeNotifier {
  bool _showSevenDayList = false;

  bool get showSevenDayList => _showSevenDayList;

  void requestSevenDayList() {
    if (_showSevenDayList) return;
    _showSevenDayList = true;
    notifyListeners();
  }

  /// Called by whichever shell acted on the request.
  void consume() => _showSevenDayList = false;
}
