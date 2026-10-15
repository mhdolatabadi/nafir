# Listening journey — first increment

The optional home card opens «سفر من»: a Saturday-based weekly goal of up to five distinct library tracks, suggestions prioritizing tracks heard less this month, persistent discovery milestones (1, 10 and 50 tracks), and a current-month listening summary. All display numbers are Persian. There are no rankings, streak penalties or automatic notifications.

Only the player's meaningful-listen callback records progress (30 seconds, or half a shorter track). Position jumps and paused position updates do not count. Replaying a track increments the monthly play count but does not duplicate weekly progress or discovery milestones.

Progress is private, account-scoped and stored in secure local storage. Signing out immediately hides it; another account cannot see it. It does **not** synchronize between devices in this increment. Switching the feature off hides the home card and stops recording without erasing earned milestones. The monthly summaries retain at most 12 months. The week and month use the device's local clock; month boundaries are Gregorian. Export and completed-month selection are follow-ups.

No backend migration or deployment configuration is needed. Rollback is reverting the client change; existing playback history remains compatible and local journey data is harmless when unused.

Follow-ups: #275 (exportable monthly image cards), #276 (server-backed collaborative goals and optional occasion collections).

Validation: Flutter analysis, 402 unit/widget tests and the Web release build pass locally. Tests include account isolation, persistence, disabled recording, Saturday rollover, seeking, paused events and a narrow RTL screen. Android compilation requires the repository CI runner; the local environment has no Android SDK.
