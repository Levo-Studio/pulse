<img src="docs/pulse-mark.svg" alt="Pulse" width="88">

# Pulse

A small ambient pixel display for iOS.

Pulse is not an app you interact with much. It is meant to be left running on a
spare phone propped up on a desk or a shelf — a dedicated little display that
shows one thing at a time, in a pixel typeface, white on pure black, with nothing
else on screen. No navigation bar, no tab bar, no status bar, no settings screen.
You swipe sideways to change what it is showing, and otherwise you leave it alone.

There are four screens: **Clock**, **Stopwatch**, **GitHub**, and **Uptime**, in
that order, reachable by horizontal swipe. The app is **dark-mode only** — there
is no light appearance and no theme switch, because a light appearance would
defeat the point.

Everything is drawn in [Silkscreen](https://kottke.org/plus/type/silkscreen/), a
bitmap pixel typeface, in uppercase with wide letter-spacing. The layout is
transcribed from a fixed design reference (`design/Pulse.dc.html`) and scaled to
whatever device it runs on, so the proportions hold from a small iPhone to an
iPad. The reference is explicitly labelled `NO GLOW`: nothing in the app draws a
shadow, a blur, or a bloom. It is meant to read like a piece of hardware, not
like a screen.

---

## Screens

Each screen below is illustrated with a hand-authored animated SVG, drawn on the
same pixel grid the app renders on — every glyph is a set of rectangles, not text
in a font. They hold still on a resting frame if your system asks for reduced
motion. They are illustrations of the layout and behaviour, not screen captures.

### Clock

The time of day as `HH:mm` in 24-hour form, with the date beneath it as a
two-letter weekday, zero-padded day, and three-letter month — `14:32` over
`FR 30 AUG`. Both lines are centred in the frame. Formatting is pinned to a POSIX
locale so the readout never localises and `HH` is genuinely 24-hour regardless of
the device's clock setting; the time zone is read from the device, so the reading
follows you if you travel.

There is nothing to operate. The clock wakes once a minute rather than once a
second, scheduled onto the next wall-clock minute boundary and recomputed from the
system clock each time, so it never accumulates drift. It also listens for
significant time changes — the clock being set, the time zone changing, midnight —
and refreshes outside the normal rhythm. It stops ticking entirely when you page
away or the app leaves the foreground.

The design reference shows a third line, `21°C`, below the date. **It is not
implemented.** No weather source is specified anywhere in the brief and the app
stores no weather credential, so the Clock screen ships as time plus date only.

<p align="center">
  <img src="docs/clock.svg" alt="Clock screen: the time advancing above the date" width="200">
</p>

### Stopwatch

A centred `HH:MM:SS` readout with the current time of day in a much fainter tone
beneath it.

**Double-tap anywhere on the screen to start and stop it, and triple-tap to reset
it to zero.** A single tap does nothing — deliberately, so that a stray touch while
the phone is being nudged around a desk cannot start or stop a run. Resetting a
running stopwatch stops it rather than restarting it from zero: the gesture is the
only route back to zero, so it has to be able to reach a *stopped* zero, and a
restart is one further double tap away.

Telling the two gestures apart is not something a pair of tap gestures can do.
Stacking `onTapGesture(count: 3)` and `onTapGesture(count: 2)` lets the two-tap
recogniser succeed the instant the second tap lands, so a triple tap starts the
stopwatch and the third tap arrives as an unrelated single tap; composing them with
`exclusively(before:)` fails the opposite way, because `TapGesture` has no failure
timeout and so the three-tap gesture never fails, leaving the double tap dead. The
screen therefore counts taps itself over a 350 ms window. Only the double tap waits
that window out, and the wait is purely visual — the toggle is recorded against the
instant the tap arrived, not the instant the window closed, so the delay never
enters the reading.

The stopwatch keeps running correctly when you swipe away from it, when you swipe
back, and while the app is in the background. That is not achieved by keeping a
timer alive: elapsed time is **derived from the timestamp at which the current run
started**, plus the total of any previous runs, and evaluated against `Date()`
whenever the view redraws. A tick that is late, coalesced, or skipped entirely
cannot make the reading wrong, because no tick ever adds to the total. The
redraw loop is purely cosmetic and only runs while the screen is the active page
and the app is in the foreground.

The state itself lives above the pager, in the app entry point, and is passed down
through the environment — `TabView` is free to tear a page down when it scrolls
off-screen, so nothing that must survive paging may be stored inside a page.

<p align="center">
  <img src="docs/stopwatch.svg" alt="Stopwatch screen: the seconds counting up while it runs" width="200">
</p>

### GitHub

Your GitHub handle and the current time along the top, then today's contribution
count as a large number over the label `COMMITS TODAY`, then a 17-column ×
7-row contribution heatmap — one column per week, one row per weekday with Sunday
at the top, oldest week on the left, today in the last column. Below the grid,
`17 WEEKS` on the left and `TODAY` on the right. Cells use a five-step monochrome
ramp; today's cell alone uses a green ramp.

On first use the screen asks for a GitHub username. It is stored in the Keychain.
Tapping the username in the header brings the prompt back, so you can point the
screen at a different account. The calendar is refreshed every 10 minutes, and
only while this screen is the one on display.

When something goes wrong, the screen says so in a single line in place of the
count and keeps whatever data it last had: `NO SUCH USER - TAP TO CHANGE`,
`NO DATA - TAP TO CHANGE`, `OFFLINE - SHOWING LAST DATA`. If today parsed but
without an exact figure, the headline shows `--` rather than a number, and the
line reads `NO COUNT FOR TODAY`. See
[Known fragility](#known-fragility-the-github-contribution-source) for why this
matters more than it looks.

The design reference shows a `LAST COMMIT AT: 13:58` line. **It is not
implemented.** The public contributions page exposes per-day totals only, never
commit timestamps, and Pulse stores no GitHub token that would let it ask for
more. The slot that line occupies is used for the status line described above.

<p align="center">
  <img src="docs/github.svg" alt="GitHub screen: the contribution heatmap filling in and today's commit count landing" width="200">
</p>

### Uptime

A `LAST CHECK` time and a `NEXT REFRESH` countdown at the top, then the list of
Levo Studio services — each row a service name against a square status dot, with
a hairline separator beneath it. Green is operational, amber degraded, red down,
and grey means no usable state was reported. The list scrolls if it is longer
than the frame.

On first open the screen asks for your own uptime API key. The field is masked,
the value goes straight to the **Keychain** and is never held anywhere else, and
the prompt says so. The list then refreshes every 20 seconds — but only while
this screen is the active page and the app is in the foreground.

Both the countdown and the poll schedule are derived from the timestamp of the
last attempt rather than from an accumulating counter, so paging away for a
minute and coming back triggers one refresh rather than replaying missed ticks.
The countdown is computed entirely client-side.

Failures are reported as what they were, in a line under the countdown:
`CONNECTION FAILED`, `SERVER ERROR: 500`, `UNREADABLE RESPONSE`, and
`REFRESH FAILED` for anything that fits none of those. A `401`
re-prompts for the key, but **does not delete the stored one** — it may be the
user's only copy of a long opaque token, and a single transient `401` during a
deploy must not destroy it; the item is overwritten only when a new value is
saved. A `403` is deliberately not treated as a rejected key: it means
authenticated but not permitted, so re-typing the same key would loop. Every
other failure leaves the previous list on screen and schedules the next attempt
normally, so a flapping API is not hammered.

Long service names are shortened rather than allowed to push the status dot off
the edge. The character budget is computed against the widest advance in
Silkscreen — the face is not fixed-pitch — so a name made entirely of wide
glyphs still cannot overrun.

> **The response schema of the uptime endpoint is unverified.** It could only be
> probed without a key, which answers
> `401 {"error":"Unauthorized","code":"UNAUTHORIZED"}`, so no successful body has
> ever been observed. `UptimeResponseDecoder` is therefore deliberately tolerant,
> and every assumption is collected in that one type: the list may be top-level or
> wrapped under one of several envelope keys; the name and state are read from the
> first matching key out of a candidate list; an unrecognised state token becomes
> `unknown` rather than an error. Numeric status codes are **not** interpreted at
> all — they are not standardised across uptime products, and reading `1` as "up"
> could paint a down service green. A non-empty list none of whose entries yielded
> a row is raised as an error rather than returned as an empty list, so an
> unrecognised name key surfaces as `UNREADABLE RESPONSE` instead of silently
> blanking the screen while the countdown keeps ticking. Once the real shape is
> known this is a one-line correction.

<p align="center">
  <img src="docs/uptime.svg" alt="Uptime screen: service status resolving with the refresh countdown ticking down" width="200">
</p>

---

## Setup

### Requirements

- **Xcode 26.2** or newer. The project targets **iOS 26.2** and uses file-system
  synchronized groups (`objectVersion = 77`), so an older Xcode will not open it.
- No package manager, no dependencies, no `pod install`, no SPM checkout. The
  only bundled asset is the Silkscreen font file.

### Build

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'generic/platform=iOS Simulator' build
```

Or just open `Pulse.xcodeproj` and run.

### Test

There is a `PulseTests` unit-test target, wired into a committed shared `Pulse`
scheme, so it runs from a clean checkout with no scheme setup:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

141 tests in 21 suites, written with Swift Testing. They cover the GitHub
contributions parser against the markup shapes it might be handed, the pixel
label's line box, the uptime response decoder, the row-truncation arithmetic, and
the uptime model's failure paths — a rejected key re-prompting without deleting
the stored one, a `403` not being mistaken for a rejected key, and a server error
being reported as itself rather than as a connection failure. Nothing in the
suite touches the network or the user's own Keychain items; the store and the API
client are injected.

#### UI tests

Whether a triple tap on the stopwatch resets without also toggling depends on how
real touches arrive at a real gesture recogniser, which no unit test can observe.
There is a separate `PulseUITests` target that drives the app on a simulator and
asserts the four gesture outcomes. It has **its own shared scheme** and is
deliberately not part of the `Pulse` scheme:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test -project Pulse.xcodeproj -scheme PulseUITests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

The stopwatch readout redraws four times a second, and XCTest has to snapshot the
accessibility tree for every query. Often enough that snapshot stalls with `Lost
connection to the application`, after which every later assertion in the run reads a
stale snapshot and fails misleadingly. Keeping the suite out of the `Pulse` scheme
keeps the command above this section deterministic. Run the UI tests deliberately
whenever the stopwatch gestures change, and re-run before believing a failure.

### First use

Nothing is configured at build time and **no credential of any kind ships in this
repository**. Only base URLs are hardcoded. You supply your own values on the
device, once:

- **GitHub screen** — asks for a GitHub username on first open. Enter your own
  handle; only the syntax is validated locally (1–39 ASCII letters, digits and
  hyphens, not leading or trailing). It is stored in the **Keychain**, and can be
  changed later by tapping the username in the header.
- **Uptime screen** — asks for an API key on first open, in a masked field. It is
  stored in the **Keychain** and is never logged, never held in the model, and
  never included in an error message.

Neither value is ever written to `UserDefaults`, to a plist, or to source. Both
are stored under the app's bundle identifier with
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, so they do not sync to
another device and do not leave in a backup.

---

## Architecture

SwiftUI throughout, no third-party code. Four source directories under `Pulse/`
(alongside `Resources/` and `Assets.xcassets/`), and the
split between them is enforced:

| Directory | Contents |
|---|---|
| `Models/` | Value types only, **no I/O**. `ClockReading` (two formatted strings), `StopwatchState` (start timestamp plus accumulated interval), `ContributionDay` / `ContributionCalendar` / `ContributionIntensity`, `UptimeService` / `UptimeStatus` and the `UptimeResponseDecoder` that builds them. |
| `Services/` | Networking, Keychain, parsing, timers. `GitHubContributionsClient`, `GitHubContributionsParser`, `UptimeAPIClient`, `KeychainStore`, `ClockTicker`. Nothing here imports SwiftUI views. |
| `PixelRendering/` | The shared display vocabulary: `PixelFont` (font registration and lookup), `PixelTheme` (the palette), `PixelLabel`, `PixelMetrics`, `ContributionHeatmapGrid`. |
| `Views/` | `PulsePager`, plus the screens under `Views/Screens/` — one file per screen, and the prompts a screen needs alongside them (`GitHubUsernamePrompt.swift`). |

`design/` holds the design reference and its runtime. It is read-only as far as
app work is concerned — never edited to make an implementation match. `docs/`
holds the brand assets and the animated illustrations this README uses, and
nothing the app itself ships. The logo PNGs there are kept as brand assets; the
README itself draws the mark from `pulse-mark.svg`.

Because the project uses file-system synchronized groups, a new file dropped
anywhere under `Pulse/` is picked up automatically; `project.pbxproj` does not
need editing to add a source file.

### The pager publishes visibility

`PulsePager` is a paged `TabView` over the `PulseScreen` enum. It writes the
currently selected screen into the environment as `\.activeScreen`, and each
screen compares that against its own case to decide whether it should be doing
work.

This is the mechanism every screen with a timer or a network call is built on:
`ClockScreen` starts and stops its ticker on it, `StopwatchScreen` keys its redraw
loop on it (combined with `scenePhase`), and both network screens key their
polling `.task(id:)` on it — `GitHubScreen` on the active screen plus the stored
username, `UptimeScreen` on the active screen plus `scenePhase` and whether a key
is present. Paging away cancels the poll loop rather than leaving the network open
behind a screen nobody is looking at. When you add a fifth screen that talks to
anything, gate it the same way.

The counterpart rule: **screens must not assume they stay alive off-screen.**
`TabView` may tear a page down. Anything that has to survive paging is either
derived from a timestamp (the stopwatch's elapsed time, the uptime countdown and
poll schedule) or held above the pager and injected (the `StopwatchState`
instance, owned by `PulseApp`).

One Swift detail worth knowing before you add a service: the project builds with
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. The uptime client, its models and its
decoder are therefore declared `nonisolated`, so the request and the response
decode do not run on the main actor behind the display. New networking and parsing
types should do the same.

### Everything is scaled, nothing is hardcoded

Every size in `design/Pulse.dc.html` is authored against a **360 × 780 pt** frame.
Screens never write those numbers as points. They write the reference number and
pass it through `PixelMetrics`, which is injected into the environment by the
pager with the real frame size:

```swift
@Environment(\.pixelMetrics) private var metrics
// ...
.padding(.top, metrics(96))          // 96 reference units, scaled
PixelLabel("COMMITS TODAY", size: 11, tracking: 4, color: PixelTheme.muted)
```

The scale factor is `min(width / 360, height / 780)`, clamped to `0.75...1.8`.
Both axes are considered because scaling on width alone would push the display
past the available height on a short, wide frame, and the clamp keeps a large
frame from scaling the type up absurdly. Fonts are requested at a *fixed* size
rather than a Dynamic Type size — the layout is already scaled, and letting it
scale twice would break the pixel grid.

If you are adding UI: read the measurement off the reference, pass it through
`metrics(_:)`, take the colour from `PixelTheme`, and draw it flat.

### The font is registered in code, not in the Info.plist

The project has `GENERATE_INFOPLIST_FILE = YES` — there is no Info.plist file in
the repository to add a `UIAppFonts` entry to. So `PixelFont.register()` is called
from `PulseApp.init()` and registers the bundled `Silkscreen-Regular.ttf` with
Core Text directly, using the **synchronous** `CTFontManagerRegisterFontsForURL`.
The asynchronous variant returns before the face is actually usable, which would
let the first frames render in a fallback face without triggering a redraw once
registration landed.

Registration failure is not fatal: `PixelFont.regular(_:)` falls back to a
monospaced system face, so a bundling mistake produces a legible-but-wrong display
rather than a proportional mess or a crash.

---

## Known fragility: the GitHub contribution source

**There is no official public API for the GitHub contribution graph.** The REST
API does not expose it, and the only endpoint that does is the authenticated
GraphQL API, which requires a token.

Pulse therefore fetches the public, unauthenticated page:

```
GET https://github.com/users/{username}/contributions
```

and **parses the HTML it returns**. GitHub can change that markup at any time,
without notice and with no version to pin, and when they do, this will break. That
is a known and accepted cost of not storing a token, not an oversight.

### The specific dependency

Exact daily counts come from `<tool-tip>` text keyed by `for` to the `id` of each
`<td data-date>` calendar cell:

```html
<td data-date="2026-08-30" id="contribution-day-component-0-52"
    data-level="1" class="ContributionCalendar-day"></td>
<tool-tip for="contribution-day-component-0-52">3 contributions on August 30th.</tool-tip>
```

The count exists *only* in that tooltip text. Attribute order is not depended on,
and the class is checked after the tag is matched rather than inside the pattern,
so a reordering or an added attribute is survivable. A renamed or restructured
`<tool-tip>` element is not.

### Why `data-level` is not a fallback

`data-level` is a bucket **relative to that account's own busiest day** — not an
absolute scale. Level 1 can mean twenty contributions on a busy account and a
single contribution on a quiet one. Converting a level back to a count is
guesswork, and the guess can be wrong by an order of magnitude while looking
completely ordinary.

So the design decision is deliberate and worth keeping if you touch this code:

- A level-derived count **may shade a heatmap cell**, and only when at most
  **three** day cells across the whole calendar are missing a tooltip
  (`levelFallbackBudget`). Every day carries an `isCountExact` flag, and the
  headline number is read from `exactCount(on:)`, which returns `nil` for an
  approximated day. The screen shows `--` rather than a number it cannot stand
  behind.
- If **no** tooltips parse at all, the parser returns nothing. If more than three
  day cells are missing one, it returns **only the days it has exact figures
  for** — the cells it cannot vouch for are dropped rather than filled in from
  their level.

The point of that second rule is the failure mode. Without it, a tooltip change
would leave the day cells parsing perfectly and the screen would confidently
display a year of fabricated numbers. With it, a wholesale change surfaces as a
**visible parse failure** — `NO DATA - TAP TO CHANGE` — and a partial one simply
leaves the unverifiable days out, so today's headline falls back to `--` and
`NO COUNT FOR TODAY` rather than to a plausible invention. Either way it is
honest, and either way it is the signal that this section of the README has come
due.

The budget is a fixed three cells rather than a proportion on purpose: a
proportional limit would let the rule quietly stop meaning what it says. At half
the calendar it would fabricate a hundred and eighty days from account-relative
levels and shade the heatmap from them without a word. Three is a handful of
cells GitHub failed to annotate — not a markup change wearing a disguise.

Nothing in the parser traps. Every match is optional, nothing is force-unwrapped,
and unrecognised markup yields an empty result that the screen renders as an empty
or stale state.

### No token, by design

Pulse stores no GitHub token and **the authenticated GraphQL API is deliberately
not used**. Requests go out on an ephemeral URL session with caching disabled, so
a scraped page is never written to the shared URL cache. If this parser breaks,
the fix is to update the parser — not to add authentication.

---

## Credits

Product by **Levo Studio** — [levo-studio.com](https://levo-studio.com)

Case study: [juliusgrimm.dev/projects/pulse](https://juliusgrimm.dev/projects/pulse)

---

## License

Pulse is open source under the **PolyForm Noncommercial License 1.0.0**. The
[`LICENSE`](LICENSE) file is authoritative; this is a summary, not a substitute.

- **Noncommercial use only.** Personal use, research, experiment, testing,
  teaching, education, and use by charitable and other noncommercial
  organizations are permitted purposes. **Any commercial use requires a separate
  licence from Levo Studio.**
- **Attribution is required.** The licence's Notices section obliges anyone who
  passes on any part of this software to pass on the licence terms and every
  plain-text `Required Notice:` line supplied with it. This project supplies one,
  so reuse and forks carry attribution to Levo Studio:

  > `Required Notice: Copyright 2026 Levo Studio (https://levo-studio.com)`

- You may make changes and derivative works for any permitted purpose, and
  distribute them, under the same terms. The licence grants no sublicensing right,
  and the software comes with no warranty.

Copyright 2026 Levo Studio.

### Third-party

The bundled **Silkscreen** typeface is not covered by the above. It is licensed
under the **SIL Open Font License 1.1** and keeps its own terms; the licence text
is retained alongside the font at
[`Pulse/Resources/Fonts/OFL.txt`](Pulse/Resources/Fonts/OFL.txt).
