# Open Wearables iPhone app

The local iOS app provides Activity, Sleep, Workouts, and Vitals summary pages.
Open **Your health summary** from the connected sync screen. Activity, sleep,
and workouts support 7-day and 30-day windows, previous/next periods, pagination,
and pull-to-refresh. Vitals shows the latest body measurements and seven-day
averages of resting heart rate and HRV. Missing measurements display a dash.

This requires the local backend's read-only SDK summary routes at
`/api/v1/sdk/users/{user_id}/summaries/{activity|sleep|workouts|vitals}`. The iOS SDK
uses the paired user's Keychain credentials and shares refresh with uploads;
no administrator API key is embedded in the app.

Run `flutter analyze` and `flutter test test/summary_test.dart` in this directory.
The build workflow runs native SDK tests on an iOS simulator before creating the
IPA. Workflow dispatch on a feature branch uploads a build artifact without
publishing a release.

Summary reads have a separate connection pool from uploads and return a cancellable
operation. Switching tabs or leaving the screen cancels the obsolete read. The
screen retains up to twelve loaded pages in memory for its lifetime; pages less
than a minute old are reused immediately. Pull-to-refresh always requests fresh
data, keeping existing values visible if the network is slow or unavailable.
No health summary cache is written to disk.
