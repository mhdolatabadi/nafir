# Listening journey — first increment

The optional home card opens «سفر من»: a Saturday-based weekly goal of up to five distinct library tracks, suggestions prioritizing tracks heard less this month, persistent discovery milestones (1, 10 and 50 tracks), and a current-month listening summary. All display numbers are Persian. There are no rankings, streak penalties or automatic notifications.

Only the player's meaningful-listen callback records progress (30 seconds, or half a shorter track). Position jumps and paused position updates do not count. Replaying a track increments the monthly play count but does not duplicate weekly progress or discovery milestones.

Progress is private, account-scoped and stored in secure local storage. Signing out immediately hides it; another account cannot see it. It does **not** synchronize between devices in this increment. Switching the feature off hides the home card and stops recording without erasing earned milestones. The monthly summaries retain at most 12 months. The week and month use the device's local clock; month boundaries are Gregorian. Export and completed-month selection are follow-ups.

No backend migration or deployment configuration is needed. Rollback is reverting the client change; existing playback history remains compatible and local journey data is harmless when unused.

Follow-ups: #275 (exportable monthly image cards), #276 (server-backed collaborative goals and optional occasion collections).

Validation: Flutter analysis, 402 unit/widget tests and the Web release build pass locally. Tests include account isolation, persistence, disabled recording, Saturday rollover, seeking, paused events and a narrow RTL screen. Android compilation requires the repository CI runner; the local environment has no Android SDK.

## Monthly image cards (#275)

«خاطرهٔ شنیدن» now lets the listener select the current month or any retained month, preview a 1080×1350 PNG, then explicitly save it using the platform file dialog (Web and Android). The image contains Persian numerals, monthly play/track counts and up to three available tracks, including their artists; no email, account identifier or private media URL is included. Month labels explicitly identify the Gregorian calendar used by the stored aggregates. No file is saved or sent automatically. The saved PNG can be shared with another app by the listener.

Empty months cannot generate a card. Cancelled saves and failures leave the preview available for retry. Changing accounts invalidates in-flight rendering and hides old previews and the old account's journey route. Rendering uses a snapshot, so listening events cannot mutate a partially generated card. Deleted/unavailable tracks are omitted from the visible top-three list while historical totals remain accurate.
