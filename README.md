# Curtain

A countdown app for iPhone, with Lock Screen and Home Screen widgets.

It exists because of one small thing other countdown apps get wrong. Set a countdown to end at
exactly 7:00 PM, look at your Lock Screen at 6:50, and most of them say **9 min**: there are
9 minutes 30 seconds left and they drop the seconds. The clock drops its seconds too, so the two
never add up, and you end up setting everything a minute late to compensate.

Curtain rounds the other way:

- **Time left is rounded up** to the smallest unit shown. At 6:50 it says **10 min**, and
  6:50 + 10 = 7:00. The countdown still ends at 7:00:00 on the dot.
- **Time since is rounded down.** Started at 9:00, the clock says 9:10, it says 10 min.

## What it does

- **Countdowns and "time since"**, named whatever you like, timed to the minute or all-day.
- **Reusable countdowns.** One that you set again and again (an end-of-shift countdown, say)
  keeps its usual times. Tap the card, tap 7:00 PM, and it is counting to the next 7:00 PM. When
  it ends it stays as one card, ready for next time.
- **Select several and delete**, with one tap to pick every finished one.
- **Lock Screen widgets**: the block under the clock (name, time, and a row of blocks, one per
  hour left) and the single line above the clock. One kind for time left, one for time since.
- **Home Screen widgets**, small and medium, in the countdown's own colours.
- **Colours**: ten ready-made sets, your own with the system colour picker, or **match my
  wallpaper**: give it a screenshot and it offers colour sets made from the picture's main colours.
  (iOS tints Lock Screen widgets itself, so colours apply to the app and Home Screen widgets.)
- New countdowns start at the next full hour, not at midnight.

Everything is saved in one file on the phone. The app never uses the network, and a picture you
show it for colours is not kept.

## Status

**Not yet run on a real iPhone.** It is built and tested on GitHub's Mac runners:

- The logic (rounding, what a widget shows and when, colours, the saved file) has unit tests that
  run on a Mac with `swift test`.
- The app is driven by UI tests in the iPhone Simulator with the clock pinned, so every number on
  screen is checked. Screenshots are kept with the logs.
- The real widget extension is placed on the simulator's Home Screen and Lock Screen by a test that
  drives iOS's own editing screens, to prove it runs and can read the app's data.

Logs and screenshots from the latest run are on the `ci-logs-core` and `ci-logs-ios` branches.

Still unknown until it is on a phone: how punctually iOS swaps the widget's text on a real Lock
Screen, how the widget looks with a real wallpaper and the always-on display, and signing.

## Installing

The widgets need the app and the widget to share a folder (an "app group"), which needs an Apple
Developer Program account to sign for. Once there is one, the app can be signed and installed from
a Windows PC or over the air. That step is not set up yet.

## How the widget keeps time

A widget can't run code every minute. It hands iOS a list of moments, each with what to show from
then on, and iOS swaps them in. `Shared/Core/TimelineBuilder.swift` builds that list: one entry
for every minute the words change, every one on a clock minute. A long countdown is planned in
stretches of three hours, and each stretch asks iOS back before it runs out. If iOS is late, the
last entry falls back to a clock text that iOS itself keeps counting, shifted so that it reads the
same as the rounded-up words.

## Code

| Where | What |
| --- | --- |
| `Shared/Core` | Plain Swift, no UI: time maths, what a widget shows, the timeline, colours and palettes, the saved file. Also a Swift package, so `swift test` runs its tests on a Mac. |
| `Shared/Platform` | Where the saved file lives, the app's clock. |
| `Shared/WidgetViews` | The widget faces, used by the widgets and by the app's preview of them. |
| `App` | The app's screens. |
| `Widgets` | The widget extension. |
| `Tests/CoreTests` | Unit tests for `Shared/Core`. |
| `UITests` | Simulator tests, including the ones that place the real widgets. |
| `tools/make_art.py` | Draws the app icon and the sample wallpaper used by tests. |

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```
xcodegen generate
```
