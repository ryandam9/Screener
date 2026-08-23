import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Points `sqflite` at an implementation that exists on the current platform.
///
/// On Android the sqflite plugin registers the default factory itself. The
/// desktop embeddings have no such plugin, so they need the FFI factory, which
/// talks to the system SQLite library directly. Calling this once before any
/// database is opened makes [MarketDatabase] platform-agnostic.
void configureDatabaseFactory() {
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}
