# Pulse — Project Rules

These rules are binding for every session in this repository. They extend the global
Levo Studio rules; where the two disagree, the rules in this file win.

---

## 1. What Pulse is

Pulse is a small ambient pixel-display iOS app. It shows five full-screen, swipeable
screens. The app is **dark-mode only** — there is no light appearance, and no user-facing
theme switch.

| # | Screen | Content |
|---|---|---|
| 1 | Clock | Large pixel-font time, date below it, local temperature with a condition indicator below that |
| 2 | Stopwatch | `00:00:00` readout, double-tap to start/stop, triple-tap to reset, small time-of-day readout below |
| 3 | GitHub | Commits-today number and contribution heatmap |
| 4 | Uptime | List of Levo Studio projects with status dots, last check time, countdown to next refresh |
| 5 | Settings | The two stored credentials and the two clock display preferences, one row each |

Behavioural requirements:

- All five screens are reachable by horizontal swipe, in the order above.
- **Stopwatch state persists across screen switches.** Swiping away from a running
  stopwatch and back must not reset or pause it. Elapsed time is derived from a start
  timestamp, never accumulated by a timer tick, so it stays correct while the screen is
  off-screen or the app is backgrounded.
- On first use the GitHub screen asks the user for their own GitHub username, and the
  Uptime screen asks for their own API key. Both are stored in the **Keychain**, never in
  `UserDefaults`, never in a plist, never in source.
- **The Settings screen is where credentials and clock preferences live**, and it is an
  additional route to them rather than a replacement: `CHANGE USERNAME` on the GitHub
  screen and `CHANGE API KEY` on the Uptime screen stay, and so do the Clock's double
  taps. It carries four rows — the uptime API key, the GitHub username, and the Clock's
  two display preferences — and it holds no state of its own:
  - The credential rows open the **same prompts** the owning screens open
    (`CredentialPromptScaffold` with `PixelCredentialField`), so masking, the reveal
    control, the notice slot and the Keychain write semantics are defined once.
  - Whether an API key is stored is answered by `KeychainStore.hasValue(for:)`, a query
    that returns **no data at all**. The key's value is never read into the screen, and
    the row says only `SET` or `NOT SET` — never the value, a prefix of it, or its
    length. The GitHub handle is not a credential and is shown in full.
  - **No row clears a credential.** A stored key may be the user's only copy of an opaque
    token — the same reasoning that forbids deleting it on a `401` — so replacing is the
    only destructive act offered.
  - The preference rows read and write the **same `ClockPreferences` instance** the Clock
    screen uses, owned by `PulsePager`. A change on either surface is immediately true on
    the other; neither screen may hold its own copy.
  - Arriving on the screen is **inert**: nothing is written, nothing is fetched, no field
    takes focus. Every mutation is a `Button` tap, so a swipe through the screen during
    ambient use cannot change anything.
- **A credential prompt releases its focus when the pager leaves its screen**, through
  `releasesFocusWhenPagedAway(from:isFocused:)`. A prompt takes focus on appear, and the
  keyboard it raises belongs to the window rather than the page, so without this it
  survives the swipe: undrawn on the next screen, but still claiming the `.keyboard`
  inset the pager deliberately honours. Centred screens only recentre; the settings
  list loses its last row and the hint beneath it, on the default first-run path where
  the uptime screen prompts for a key and the next swipe lands on settings. Every prompt
  must pass the screen it is drawn on, because settings shows the same prompts as the
  screens that own the credentials.
- The Clock screen has two display preferences, both toggled by a double tap and both
  stored in `UserDefaults` under a `clock.` prefix — never the Keychain, which is reserved
  for credentials:
  - a double tap on the **time** switches between `HH:mm` and `HH:mm:ss`, and the ticker's
    wake-up cadence follows, going back to minute-boundary scheduling when seconds are
    hidden. Default off.
  - a double tap on the **weather line** hides or shows the condition indicator. The
    temperature stays either way. Default on.

  Each gesture is scoped with its own `contentShape`, so neither can trigger the other, and
  a tap gesture yields to the pager's horizontal drag so swiping between screens still
  works.

---

## 2. Design source of truth

The reference design lives at **`design/Pulse.dc.html`** (with its runtime,
`design/support.js`). It is a Claude Design canvas export.

**Every screen must be implemented by first opening that file and closely matching it** —
colors, spacing, pixel-grid density, and glow treatment. Do not design from the
description in this file or from memory; the HTML is authoritative.

If a detail is not visible in the reference, **do not guess** — implement the most
conservative reading and record the ambiguity in the pull request description.

The reference has **no settings frame and no onboarding frame**. Those screens are
therefore assembled from the vocabulary the reference does define — the pure black
field, the `PixelTheme` palette, letter-spaced uppercase pixel labels, flat surfaces,
no glow — and they borrow an existing pattern rather than inventing one: the settings
rows are the uptime list's row, name on the left and an indicator square on the right,
20 units of vertical padding and a one-unit `PixelTheme.separator` hairline, with the
row's current value on a second, fainter line under the name.

### Tokens extracted from the reference

These are transcribed from `design/Pulse.dc.html` for convenience. If they ever disagree
with the file, **the file wins** — re-read it and correct this table.

The reference is titled `AMBIENT PIXEL DISPLAY / NO GLOW`, variant `1B — PURE BLACK & WHITE`.

Screen surface and type:

| Token | Value | Used for |
|---|---|---|
| Screen background | `#000000` | All five screens |
| Primary text | `#FFFFFF` | Clock time, stopwatch time, commit count |
| Bright label | `#E6E6E6` | GitHub username, uptime service names |
| Secondary label | `#525252` | Date, clock temperature and its condition indicator, "COMMITS TODAY", the bare last-commit time above it |
| Tertiary label | `#3D3D3D` | Time-of-day readout, "LAST CHECK", "NEXT REFRESH", axis labels |
| Row separator | `#1C1C1C` | Uptime list row bottom border |

Typeface is **Silkscreen** (SIL Open Font License 1.1), bundled in the app. All display
copy is uppercase and letter-spaced.

Type scale, at the reference frame width of 360 pt:

| Element | Size | Letter spacing |
|---|---|---|
| Clock time, `HH:mm` | 70 | 2 |
| Clock time, `HH:mm:ss` | 48 | 2 |
| Clock date | 16 | 5 |
| Clock temperature | 16 | 5 |
| Stopwatch time | 48 | 2 |
| Stopwatch time-of-day | 14 | 4 |
| GitHub commit count | 76 | 1 |
| GitHub "COMMITS TODAY" | 11 | 4 |
| GitHub last-commit time | 16 | 4 |
| GitHub header row | 10 | 2 |
| Heatmap axis labels | 9 | 2 |
| Uptime service name | 13 | 2 |
| Uptime meta lines | 10 | 2 |

Sizes are authored against a 360 pt-wide frame. Scale them proportionally to the actual
screen width rather than hardcoding, so the layout holds from a small iPhone to an iPad.

GitHub heatmap:

- 17 columns × 7 rows, 119 cells, `5 px` gap at 360 pt width, square cells.
- Monochrome intensity ramp, five steps:
  `#141414` → `#3D3D3D` → `#6E6E6E` → `#A3A3A3` → `#FFFFFF`
- Today's cell uses a separate green ramp:
  `#123A20` → `#166534` → `#199C48` → `#22C55E` → `#4ADE80`
- Intensity step from commit count: `0` → 0, `1–2` → 1, `3–5` → 2, `6–9` → 3, `10+` → 4.
- Axis labels below the grid: `17 WEEKS` on the left in `#3D3D3D`, `TODAY` on the right in
  `#FFFFFF`.

Uptime status dots — `11 × 11` at 360 pt width, square, no border:

| State | Color |
|---|---|
| Operational | `#22C55E` |
| Degraded | `#F59E0B` |
| Down | `#EF4444` |
| Unknown / no data | `#2A2D2E` |

**No glow.** The reference is explicitly labelled `NO GLOW`. Do not add shadows, blurs,
bloom, or `.shadow(...)` to any display element.

### Known ambiguities in the reference

Carry these forward; do not silently resolve them.

- The GitHub screen's layout departs from the frame in three ways, all **explicit
  direction from the repository owner**, none of them oversights. Do not "correct" any
  of them back to the reference.
  - The reference's `LAST COMMIT AT:` **label is dropped**. The time is drawn bare,
    centred directly above the commit count, at size 16 in `#525252` — the same grey as
    `COMMITS TODAY` below the count, so the two bracket the white number as one block.
    The screen therefore carries two unlabelled times: this one and the header's clock.
    They are separated on every other axis — the header is 10, `#3D3D3D`, right-aligned
    in the top row, `HH:mm:ss` and ticking; this one is 16, `#525252`, centred mid
    screen, `HH:mm` and static. Keep that separation if either is ever restyled. Its
    tracking is **4, not 5**: 16 at 5 in `#525252` is the Clock screen's own date and
    temperature style character for character, and this time must not quote the screen
    that really is a clock. 4 is the tracking of `COMMITS TODAY` below it.
  - The **pull request line is removed**, and with it the summary's opened and merged
    counters and the events client's classification of pull request actions. Do not
    reintroduce a count from the events feed. The feed is still fetched: it supplies the
    time above the count and the freshness line.
  - The reference's **fixed vertical offsets are not transcribed**. `+96` to the count
    and `+110` to the heatmap were authored for the 360 × 780 frame, and a frame taller
    than that has to put the leftover height somewhere. Transcribed literally it all
    lands in one place — the trailing spacer above `CHANGE USERNAME` — which splits the
    footer rather than sharing the space: measured, 117 points of gap between
    `LAST CHECK` and `CHANGE USERNAME` at 393 × 852 and 58 at 375 × 667. The screen
    distributes its space instead — header at the top, count block optically centred,
    heatmap and axis below it, footer together at the foot — with gaps that flex and
    floors that hold on the shortest supported screen. Type sizes, colours and heatmap
    density are unchanged, and the blocks keep their own internal spacing exactly as
    drawn.
  - The heatmap **is laid out before those gaps** (`layoutPriority(1)`). Its cells are
    square by aspect ratio, so height it is not granted comes back as width it does not
    draw: without the priority the grid rendered 252 points wide of an available 330 at
    375 × 667, inset from an axis row that still spanned the full width. Do not remove
    it.
  - `GitHubScreenLayoutTests` renders the screen at 375 × 667 and 393 × 852 and pins
    where its elements land: eight bands in order, the header on the reference's 70 unit
    inset, the footer's two lines together at the foot, the count block centred between
    the header and the grid, and the grid at the full content width. It locates each
    band by the palette colour that draws it, **not** by how bright the render is — an
    empty heatmap is `#141414` and a brightness threshold does not see it at all.
- The GitHub frame shows `LAST COMMIT AT: 13:58`. The contributions page exposes only
  per-day totals, so the line is sourced from the public events API instead (see §3),
  from the newest public push **of today**. Two caveats stand: the feed timestamps the
  push, not the authoring of the commit inside it, and it sees public activity only, so
  a day's work in a private repository is invisible to it. The time is scoped to today
  because it carries no date and sits directly above a `COMMITS TODAY` headline, where a
  time from earlier in the 90-day window would read as today's. With no public push today it
  is omitted, never placeheld and never filled with an older one.
- The GitHub header shows the current time as `HH:MM:SS`, where the reference frame
  shows `14:32` and only the uptime frame uses seconds. This is a **deliberate
  deviation, requested explicitly by the repository owner** — not an oversight and not a
  transcription error. Do not "correct" it back to `HH:MM`. The one-second ticker behind
  it runs only while the screen is visible and the app is foregrounded.
- The Clock's `HH:mm:ss` readout is set at **48**, not the reference's 70. This is forced,
  not a preference: measured from the bundled face, Silkscreen advances its wide digits
  0.75 em and its colon 0.375 em, so `HH:mm:ss` at 70 is **383.5** reference units against
  a content width of **308** — the 360 unit frame less 26 units of padding either side,
  which is also the narrowest budget any supported display offers. It overruns by 75.5
  units and `PixelLabel` neither wraps nor compresses, so it would run off both edges.
  48 is **the size the reference itself gives its own eight-character readout**, the
  stopwatch's `00:00:00`, so the two agree and the number is the design's rather than an
  invention; it measures 268. The `HH:mm` readout keeps the reference's 70 untouched.
  Sizes in the low fifties also fit arithmetically — the ceiling is 55.6 — and were not
  used because none of them appears in the design and the largest scrape the limit.
  The advance table lives in `ClockTimeMetrics` and is checked against the bundled font
  through Core Text, not against hardcoded numbers, so it cannot quietly describe a font
  the app does not ship.
- The frames are drawn with a `7 px #1B1D1E` rounded border. That is device-bezel chrome in
  the canvas mock, not app UI. Do not draw a border inside the app.

---

## 3. APIs

Only **base URLs** may be hardcoded. No key, token, username, or other credential appears
in source, in a plist, in a test fixture, or anywhere in git history.

### Uptime

```
GET https://tickets.levo-studio.com/api/uptime/listall
Authorization: Bearer <key>
```

- The key is entered by the user on first use and stored in the Keychain. Keys are
  prefixed **`lsu_`**. Never log it, never write it to source, a plist or a fixture.
- Poll every **20 seconds, only while the Uptime screen is visible.** Polling stops when
  the user swipes away and when the app leaves the foreground.
- The countdown to the next refresh is computed **client-side** from the timestamp of the
  last request.

**Response schema — documented by the repository owner, authoritative.** The project list
is at `data.projects`; the calling key's metadata is at `data.key`.

```json
{
  "data": {
    "key": { "id": "uuid", "name": "Statuspage", "keyPrefix": "lsu_abcd1234" },
    "projects": [
      {
        "id": "notion-page-id",
        "name": "Levo Studio Analytics",
        "customer": "Julius Grimm",
        "domain": "analytics.levo-studio.com",
        "category": "apps-internal",
        "serverLocation": "DE",
        "hostingPrice": 42,
        "currentStatus": "up",
        "lastCheckedAt": "2026-06-13T12:00:00.000Z",
        "lastStatusChangeAt": "2026-06-13T11:30:00.000Z",
        "monitoringPausedAt": null,
        "consecutiveFailureCount": 0,
        "summary": {
          "totalChecks": 120, "successfulChecks": 118, "degradedChecks": 2,
          "downChecks": 0, "uptimePercent": 100, "avgResponseMs": 180,
          "medianResponseMs": 170, "p95ResponseMs": 260, "minResponseMs": 120,
          "maxResponseMs": 3200, "latestResponseMs": 175,
          "latestCheckedAt": "2026-06-13T12:00:00.000Z", "incidentCount": 0
        }
      }
    ]
  }
}
```

- Decoding is plain `Codable` against this shape. Only the fields the screen draws are
  decoded — `name`, `currentStatus`, `lastCheckedAt` — and every other field is ignored
  rather than rejected, so the endpoint can grow without breaking the app.
- Strictness follows one rule: **a field the screen cannot render without is required; a
  field it can live without degrades rather than failing the response.**
  - Strict: `data`, `projects`, and each project's `name`. A **missing `data` or
    `projects` member is an error**, not an empty result — an empty list and a response
    that is not this shape must never look the same on screen. A project with no name has
    no row to draw.
  - Lenient: `currentStatus` degrades to `unknown`, and `lastCheckedAt` — absent,
    misspelled, or sent as the wrong type — degrades to no timestamp for that project.
    The row still draws with its status. Failing the whole response over a field no row
    needs would blank the screen for nothing.
- `data.key.keyPrefix` is **deliberately not decoded.** It is a fragment of the user's own
  bearer token and the app has no use for it; a value never held cannot be leaked.
- `currentStatus` is one of **`up`, `slow`, `degraded`, `down`, `unknown`**. Only `down`
  reduces the reported uptime percentage. The reference draws four colours, so the mapping
  is:

  | `currentStatus` | Square | Colour |
  |---|---|---|
  | `up` | Operational | `#22C55E` |
  | `slow`, `degraded` | Degraded | `#F59E0B` |
  | `down` | Down | `#EF4444` |
  | `unknown`, absent, **anything else** | Unknown | `#2A2D2E` |

  A value outside that vocabulary maps to **unknown, never to a guessed state**. The
  mapping lives only in `UptimeStatus.init(apiValue:)`.
- `LAST CHECK` is drawn from the newest `lastCheckedAt` in the response — the API's own
  clock, when the states on screen were actually observed — not from when the app last
  fetched. With no usable timestamp in the response the line stays as dashes; the device's
  fetch time is never substituted for it, because the two are different quantities and the
  line carries no label distinguishing them.
- A `lastCheckedAt` **ahead of the device clock is drawn as sent, not clamped to now.**
  The line reports the API's clock, and rewriting a skewed timestamp into a plausible one
  would hide the skew rather than show it.

Errors:

- `401 {"error":"Unauthorized","code":"UNAUTHORIZED"}` — missing or invalid key. Handled as
  "key rejected": re-prompt rather than showing a network error, and **never delete the
  stored key**, which may be the user's only copy.
- `403` is **not** folded into that. Authenticated but not permitted cannot be fixed by
  re-typing the same key, so it is reported as a server error.
- `404 PROJECT_NOT_FOUND` — names a single project, and `listall` names none, so it has no
  distinct meaning on this endpoint and gets no case of its own; it is reported as a
  server error like any other unexpected status.
- `500` — server error, reported as itself.

### GitHub contributions

```
GET https://github.com/users/{username}/contributions
```

Unauthenticated, public.

> **Known fragility.** There is no official public API for the contribution graph. This
> endpoint returns an HTML fragment that is parsed for per-day counts. GitHub can change
> that markup at any time without notice, which will break parsing. Parsing failure must
> degrade gracefully — show an empty or stale state, never crash.

This constraint must be restated in a comment at the parser and in the README.

**Do not** switch to the authenticated GraphQL API. Pulse stores no GitHub token by design.

### GitHub public events

```
GET https://api.github.com/users/{username}/events/public?per_page=100
Accept: application/vnd.github+json
```

Unauthenticated, public, and **no token is stored** — the same standing rule as every
other source in this app. Only the base URL is hardcoded; the username comes from the
Keychain.

This is the second GitHub source and it does not replace the first. It is a documented
JSON API rather than scraped markup, and it is where the bare time above the screen's
count and the freshness line come from. The heatmap and the
commits-today headline stay on the contributions page: only that source has per-day
totals.

Everything the screen draws from this feed is **scoped to the user's own today**, in the
device's time zone. The window is 90 days deep and nothing on the screen carries a date, so an unscoped figure from it would
be read as today's. Where there is nothing today, the line is omitted.

Its limits are part of the contract and must be carried into anything built on it:

- **Public activity only.** Contributions to private repositories never appear here,
  whatever the account's "include private contributions" setting does to the heatmap.
  The two sources may therefore legitimately disagree, and usually in one direction —
  the heatmap shows more than the events imply. **Do not reconcile them.** Anything
  rendered from this feed is labelled as public so it cannot be read as an account-wide
  total.
- **60 requests per hour per IP**, shared with everyone else behind that address, so the
  quota can be spent by someone else entirely. Exhaustion answers `403` (or `429`) with
  `x-ratelimit-remaining: 0`. That must degrade gracefully: keep showing the last good
  data, back off until `x-ratelimit-reset`, never spin, never crash. This endpoint is
  polled no more often than the contributions page and reuses its cadence.
- **A window, not a history** — roughly the last 300 events or 90 days. Ample for
  "today"; it must never be presented as a record of anything longer.
- **Events lag reality by up to about five minutes**, which is why the screen states
  when it last fetched rather than implying live data.

### Weather

```
GET https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&current=temperature_2m,weather_code
```

Feeds the Clock screen's third line — the temperature the reference draws as `21°C`, and
the condition indicator beside it.

**Open-Meteo, and only Open-Meteo.** It needs **no API key, no account and no token**,
which is why it was chosen: the rule above forbids a credential in source, in a plist or in
git history, and this endpoint requires none. The base URL is the only thing hardcoded and
the only thing there is. It is a European open-data service, which matters for this
project's data-handling rules.

Do not substitute WeatherKit, OpenWeatherMap, or anything else. WeatherKit in particular
needs a paid-account entitlement the project does not have.

- Response shape, verified against the live endpoint:

  ```json
  {
    "current_units": { "temperature_2m": "°C", "weather_code": "wmo code" },
    "current": { "time": "2026-08-30T09:00", "temperature_2m": 21.3, "weather_code": 3 }
  }
  ```

- The **temperature unit is checked, not assumed.** Celsius is the service's default and
  the request asks for nothing else, but the display draws a literal `°C`, so a response in
  another unit is treated as malformed rather than mislabelled.
- `weather_code` is a **WMO 4677** present-weather code, collapsed into six drawn
  conditions — clear, cloudy, fog, rain, snow, thunderstorm. The mapping lives in exactly
  one place, `WeatherCondition.init(wmoCode:)`, with its full table in that initialiser's
  doc comment. Do not duplicate it. Freezing drizzle and freezing rain map to `rain`: the
  indicator says what is falling, not what it does when it lands.
- A **missing or unmapped code costs the indicator only.** The temperature is still shown.
  An unknown code is never guessed at and never drawn as a question mark.
- The indicator is **drawn as pixel art on the display's own grid** — an eight-by-seven
  bitmap of flat square cells, in `PixelWeatherIcon`. **Not** an SF Symbol and **not** an
  emoji: either would arrive with its own curves and colour beside a bitmap typeface and
  read as pasted in from another app.
- U+00B0 DEGREE SIGN **is present in the bundled Silkscreen face** — glyph 190, advance
  0.625 em, drawn as a hollow square between 0.25 and 0.625 em above the baseline — so
  `21°C` renders in the pixel typeface with no substitution and no fallback.

Location:

- Coordinates come from **CoreLocation at reduced accuracy** (`kCLLocationAccuracyReduced`).
  A temperature to the nearest degree does not need a precise fix.
- **When-in-use** authorisation only, requested the first time the Clock screen needs a
  coordinate — never at launch. The usage string is the
  `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` build setting; the project generates
  its Info.plist and has no file to edit.
- The coordinate is **coarsened to two decimal places** before it is sent, is held only for
  the duration of one lookup, and is **never logged and never persisted**.

Refresh and failure:

- Fetch once when the Clock becomes the active screen, then every **30 minutes**. Open-Meteo
  advances its `current` block on a 15 minute grid, the display shows whole degrees, and
  two requests an hour is a courteous load on a free, unauthenticated service. Stops when
  the screen is paged away and when the app leaves the foreground, like the Uptime poll.
- The last reading is **cached across paging** so returning to the Clock does not blank the
  line, and is dropped once it is three hours old.
- **Every failure degrades to absence.** Refused authorisation, no fix, an unreachable
  service, an unreadable body — the temperature line is simply not drawn and the Clock
  renders exactly as time plus date. There is **no error text, no placeholder and no
  dash**: the reference has no failure state for this line and an ambient display should
  not nag. The time and the date are never blocked, delayed or degraded by weather or
  location work.
- The Clock's vertical gaps are stated as **top padding on each line rather than as stack
  spacing**, because the reference does not space the three lines evenly: it sets `gap: 20`
  on the container and adds `margin-top: 26` to the temperature alone. One shared spacing
  value cannot say that. This is about expressing the reference, **not** about the absent
  line — SwiftUI does not charge stack spacing for a conditional child whose condition is
  false, so absence costs nothing under either arrangement. `ClockLayoutTests` renders both
  and pins it.
- The absence path is verified by **rendering the view and comparing pixels**
  (`ClockLayoutTests`), not by eyeballing screenshots. Two screenshots of a running clock
  are taken at different times and differ in the digits, which is exactly the slack that
  hides a layout regression.

---

## 4. Repository layout

```
Pulse/
  Models/            Value types, no I/O
  Services/          Networking, Keychain, parsing, timers
  PixelRendering/    Pixel font loading, grid primitives, heatmap
  Views/             One folder or file per screen, plus the paging container
  Resources/         Bundled font files
design/              Claude Design reference — read-only, never edited by app work
```

The Xcode project uses **file-system synchronized groups** (`objectVersion = 77`). Files
added under `Pulse/` are picked up automatically; `project.pbxproj` does not need editing
to add a source file.

---

## 5. Code quality

- SwiftUI only.
- **English everywhere** — code, identifiers, comments, commit messages, PR titles and
  bodies, and all user-facing copy.
- No force-unwraps and no `try!` without an adjacent comment justifying why the value
  cannot be absent.
- No `TODO`, `FIXME`, or commented-out code on a branch being proposed for merge. An open
  question goes in the PR description, not in the source.
- Doc comments (`///`) on every public type and public member.
- SwiftLint must be clean before merge. If SwiftLint is not installed on the machine, say
  so explicitly in the PR rather than claiming the check passed.
- Respect `prefers-reduced-motion` (`accessibilityReduceMotion`) for any animation.
- Verify before claiming done. The build command is:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'generic/platform=iOS Simulator' build
```

---

## 6. Git workflow

- **`main` always builds and stays demoable.** Never push a broken `main`.
- One working branch per screen or feature, named per the global prefix convention
  (`feat/`, `fix/`, `docs/`, `chore/`, …). Never `claude/`.
- An implementing agent works on the branch; a **second, independent agent reviews it**
  before merge — checking design adherence against `design/Pulse.dc.html`, absence of
  secrets, code quality, and correct API usage.
- The orchestrating agent merges reviewed branches into `main` and pushes.
- Sub-agents **commit and push their own branch continuously**. Never end a turn with
  uncommitted or unpushed work.

### Commit and PR messages

Conventional Commits, plain, describing the change only.

**Never** reference a session, an agent, Claude, Anthropic, AI assistance, a session ID, or
any other meta-information about how the change was produced. No `Co-Authored-By: Claude`,
no "Generated with" footers. Commits and PRs read as if written by hand.

### Remote and background sessions

Progress must be written into **commit messages and PR descriptions**, not left in session
context. Any agent or resumed session must be able to read the branch's history and PR body
and pick up correctly with no human present. State what is done, what is not, and what the
next step is.

---

## 7. Security

- No secrets in source or in git history — only base URLs.
- The user's GitHub username and Uptime API key live in the **Keychain** only.
- Never read, print, `cat`, or `grep` `.env` files or any credential store.
- Never log a credential, a full request header, or a raw response body that could contain
  one.

---

## 8. License and attribution

Pulse is open source under **PolyForm Noncommercial 1.0.0** — non-commercial use only, with
attribution to Levo Studio required for reuse or forks. The `LICENSE` file is authoritative.

The company name is always written **Levo Studio**, both words, never "Levo" alone.

Bundled third-party assets keep their own licenses: the Silkscreen typeface ships under the
SIL Open Font License 1.1, with the license text retained alongside the font files.
