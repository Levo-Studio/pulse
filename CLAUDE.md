# Pulse — Project Rules

These rules are binding for every session in this repository. They extend the global
Levo Studio rules; where the two disagree, the rules in this file win.

---

## 1. What Pulse is

Pulse is a small ambient pixel-display iOS app. It shows four full-screen, swipeable
screens. The app is **dark-mode only** — there is no light appearance, and no user-facing
theme switch.

| # | Screen | Content |
|---|---|---|
| 1 | Clock | Large pixel-font time, date below it |
| 2 | Stopwatch | `00:00:00` readout, double-tap to start/stop, small time-of-day readout below |
| 3 | GitHub | Commits-today number and contribution heatmap |
| 4 | Uptime | List of Levo Studio projects with status dots, last check time, countdown to next refresh |

Behavioural requirements:

- All four screens are reachable by horizontal swipe, in the order above.
- **Stopwatch state persists across screen switches.** Swiping away from a running
  stopwatch and back must not reset or pause it. Elapsed time is derived from a start
  timestamp, never accumulated by a timer tick, so it stays correct while the screen is
  off-screen or the app is backgrounded.
- On first use the GitHub screen asks the user for their own GitHub username, and the
  Uptime screen asks for their own API key. Both are stored in the **Keychain**, never in
  `UserDefaults`, never in a plist, never in source.

---

## 2. Design source of truth

The reference design lives at **`design/Pulse.dc.html`** (with its runtime,
`design/support.js`). It is a Claude Design canvas export.

**Every screen must be implemented by first opening that file and closely matching it** —
colors, spacing, pixel-grid density, and glow treatment. Do not design from the
description in this file or from memory; the HTML is authoritative.

If a detail is not visible in the reference, **do not guess** — implement the most
conservative reading and record the ambiguity in the pull request description.

### Tokens extracted from the reference

These are transcribed from `design/Pulse.dc.html` for convenience. If they ever disagree
with the file, **the file wins** — re-read it and correct this table.

The reference is titled `AMBIENT PIXEL DISPLAY / NO GLOW`, variant `1B — PURE BLACK & WHITE`.

Screen surface and type:

| Token | Value | Used for |
|---|---|---|
| Screen background | `#000000` | All four screens |
| Primary text | `#FFFFFF` | Clock time, stopwatch time, commit count |
| Bright label | `#E6E6E6` | GitHub username, uptime service names |
| Secondary label | `#525252` | Date, "COMMITS TODAY", "LAST COMMIT AT" |
| Tertiary label | `#3D3D3D` | Time-of-day readout, "LAST CHECK", "NEXT REFRESH", axis labels |
| Row separator | `#1C1C1C` | Uptime list row bottom border |

Typeface is **Silkscreen** (SIL Open Font License 1.1), bundled in the app. All display
copy is uppercase and letter-spaced.

Type scale, at the reference frame width of 360 pt:

| Element | Size | Letter spacing |
|---|---|---|
| Clock time | 70 | 2 |
| Clock date | 16 | 5 |
| Stopwatch time | 48 | 2 |
| Stopwatch time-of-day | 14 | 4 |
| GitHub commit count | 76 | 1 |
| GitHub "COMMITS TODAY" | 11 | 4 |
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

- The Clock frame shows a third line, `21°C`, below the date. No weather source is
  specified anywhere in the brief and the app stores no weather API credential. It is
  **not implemented**; the Clock screen ships as time plus date only.
- The GitHub frame shows `LAST COMMIT AT: 13:58`. The contributions page exposes only
  per-day totals, so the line is sourced from the public events API instead (see §3),
  from the newest public push **of today**. Two caveats stand: the feed timestamps the
  push, not the authoring of the commit inside it, and it sees public activity only, so
  a day's work in a private repository is invisible to it. The line is scoped to today
  because it carries no date and sits under a `COMMITS TODAY` headline, where a time
  from earlier in the 90-day window would read as today's. With no public push today it
  is omitted, never placeheld and never filled with an older one.
- The GitHub header shows the current time as `HH:MM:SS`, where the reference frame
  shows `14:32` and only the uptime frame uses seconds. This is a **deliberate
  deviation, requested explicitly by the repository owner** — not an oversight and not a
  transcription error. Do not "correct" it back to `HH:MM`. The one-second ticker behind
  it runs only while the screen is visible and the app is foregrounded.
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

- The key is entered by the user on first use and stored in the Keychain.
- Poll every **20 seconds, only while the Uptime screen is visible.** Polling stops when
  the user swipes away and when the app leaves the foreground.
- The countdown to the next refresh is computed **client-side** from the last check time.
- An unauthenticated request returns `401 {"error":"Unauthorized","code":"UNAUTHORIZED"}`.
  Handle that as "key rejected" and re-prompt, rather than showing it as a network error.

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
JSON API rather than scraped markup, and it is where the screen's `LAST COMMIT AT` line,
today's pull request activity and the freshness line come from. The heatmap and the
commits-today headline stay on the contributions page: only that source has per-day
totals.

Everything the screen draws from this feed is **scoped to the user's own today**, in the
device's time zone — the last push as much as the pull request counts. The window is 90
days deep and nothing on the screen carries a date, so an unscoped figure from it would
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
