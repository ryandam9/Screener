# Screener

A Flutter app that reads the growth-screener SQLite files the pipeline
publishes to `s3://hive-in-the-cloud/{us.db,asx.db,nse.db}`. Ships to Android
and Linux desktop.

A market is one value of the `Market` enum and one file in the bucket; the
database layer discovers tables by shape, so a new file needs no schema work.
Add markets at the end of the enum — notification ids come off the index.

## Shipping a change

Every change goes the whole way, without being asked each time:

1. Develop on `claude/flutter-s3-sqlite-android-lan40w`, creating it from
   `main` if it is not there.
2. `flutter analyze` and `flutter test` clean before committing. A change to
   behaviour comes with a test, and the test is proved by reverting the fix
   and watching it fail.
3. Commit and push to that branch.
4. Open a PR against `main` — the repo has no `master`, whatever the request
   calls it.
5. Merge it.
6. `git checkout main && git pull origin main`.

## Verifying UI work

Widget tests do not settle a layout or colour question. Build the real thing
and look at it:

```
flutter build linux --release
Xvfb :99 -screen 0 400x760x24 &   # DISPLAY=:99
./build/linux/x64/release/bundle/screener &
xdotool search --name "Stocks Analysis"   # then windowsize to 320x640
import -window root shot.png
```

For a before/after, `git stash` the change, rebuild, shoot, then pop and
compare with `convert a.png b.png +append`.

Two things cannot be checked in this container, and are worth saying so
rather than implying otherwise: there is no Android SDK, so no APK build or
on-device check; and there is no session D-Bus, so Linux notifications
cannot be posted.
