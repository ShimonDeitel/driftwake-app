# Driftwake — Sleep-Onset Alarm

## Concept
An alarm that wakes you a precise duration *after you actually fall asleep*,
not at a fixed clock time. Driftwake detects the moment sleep onset happens
using on-device signals (CoreMotion accelerometer stillness + microphone
amplitude), then counts a chosen duration — plain hours, or whole 90-minute
sleep-cycle multiples — forward from that moment.

## Problem
Clock-time alarms ("wake me at 6:40am") ignore how long you actually slept.
If you take 40 minutes to fall asleep, a "sleep for 8 hours" clock alarm
either wakes you 40 minutes early or late relative to your real sleep debt.
Existing sleep apps (Sleep Cycle, Sleepzy, RISE) all still schedule around a
clock-time window, not true sleep-onset.

## Evidence
Sourced from the Animated Ten research pass (`pulse/ANIMATED_TEN_QUEUE.md`):
a Quora asker posed this exact "wake me N hours after I actually fall asleep"
question with no existing app named in any answer.

## Core detection heuristic
Real, testable, no ML model:
- Motion: `MotionMonitor` aggregates raw `CMDeviceMotion` user-acceleration
  magnitude into a per-minute sample variance.
- Mic: `MicMonitor` aggregates `AVAudioRecorder` metering (`averagePower`)
  into a per-minute amplitude variance, entirely on-device.
- `SleepOnsetDetector.detectOnsetIndex` scans the combined per-minute
  variance stream for the first run of `sustainedMinutes` (default 8)
  consecutive minutes at or below `varianceThreshold` (default 0.02) and
  reports the *start* of that run as the onset minute — the same "onset
  back-dated to when stillness began" approach real actigraphy sleep-onset
  detection uses.

## Free vs Pro
- **Free**: one fixed anchor profile. No automatic detection — the user taps
  "I'm about to sleep" and that tap *is* the onset (manual anchor tagging).
- **Pro ($4.99/mo)**: automatic motion/mic onset detection (no tap needed),
  multiple saved anchor profiles, and the AI nightly insight.

## Quirky feature — second-chance snooze
When the alarm fires and the user hits snooze, `SnoozeEvaluator` inspects the
motion/mic variance samples from the snooze window:
- Sustained near-zero variance (`deepSleepCeiling`, default 0.004) for at
  least `sustainedMinutesForLockout` (default 6) minutes → **hard lockout**:
  the snooze button is disabled with a plain-language explanation ("this
  looks like deep sleep, so snooze is off the table tonight").
- Anything else (low but nonzero variance, i.e. still in bed but not
  flatlined) → the **second-chance snooze** button is shown and works
  normally.

## Animation hook
On the main screen, `EmberView` is a small circular ember/star icon that
flickers continuously (`TimelineView(.animation)`, phase driven by layered
sine waves so it never repeats identically) while Driftwake is watching for
onset. The instant onset locks, the flicker stops — a distinct spring-based
"onset-lock" transition snaps the ember to a steady glow. At the same moment,
`CountdownRingView` (a `Canvas`-drawn arc, also time-driven) begins tracing
from empty toward a full circle as real time advances from onset toward the
anchored wake point.

## AI feature (text, Pro only)
Each morning the user logs a 1–5 grogginess rating tied to that night's
anchor duration. `AIInsightService` takes the last 14 days of
`{anchorDurationHours, grogginessRating}` pairs, POSTs them to
`https://apps-ai-proxy.s0533495227.workers.dev/text` asking the model to spot
a correlation and reply with exactly one plain sentence suggesting a specific
alternate anchor duration (e.g. "You feel sharper at 5.5 hours than 6 — try
that tonight."). No API key; the shared Worker is stateless and keeps no
server-side history — only the on-device 14-day log persists.

## Design direction
Midnight indigo-to-charcoal gradient background (dark = the app's home look,
light = a softer "dusk" variant, never a stark white sheet). Single warm
ember-orange accent color. Every shape in the main UI chrome is circular or
orbital — rings, arcs, halos, dots — no straight edges or rectangles behind
the ember/ring/anchor-picker chrome (list rows in Settings/profile
management use standard system Form styling, which is out of that "main UI
chrome" scope).

## Monetization
Auto-renewable monthly subscription, product id
`com.shimondeitel.driftwake.pro.monthly`, $4.99/month, implemented with
StoreKit 2 (`Transaction.currentEntitlements` / `Transaction.updates`).

## Known limitations (honest, not overclaimed)
Continuous overnight motion/mic monitoring needs the app to stay alive in
the background; Driftwake requests the `audio` background mode (the same
technique used by white-noise/sleep-tracking apps) to keep sampling while
the phone is face-down on the nightstand. If iOS still suspends the app
(low battery, force-quit, etc.) automatic onset detection stops and the
free-tier manual "I'm about to sleep" tap remains the reliable fallback —
this is disclosed in-app, not hidden.
