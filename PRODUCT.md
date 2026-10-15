# Product

<!-- impeccable:product-schema 1 -->

> Written for #236 without the usual interview: the work ran unattended, so
> every fact below comes from the repository (AGENTS.md, docs/, the app and
> server code, issues). Facts marked *(inferred)* are a best reading of that
> evidence; the owner should confirm or correct them.

## Platform

android

One Flutter UI ships as the Android app and as the web app at `/app/`; it
does not change its design language per platform. Android is the primary
store distribution (Cafe Bazaar, Google Play); the web build is the second
supported client. iOS is out of scope (AGENTS.md).

## Users

- **Persian-speaking listeners with their own music collection** *(inferred
  from the Persian-only copy, Bazaar listing and features)*: people with
  files on their phone, songs saved from Telegram or Bale, or links to
  song pages, who want one library that plays everywhere.
- **Friends sharing music**: they make playlists together (collaborative
  playlists), share them by link, and browse public playlists, often as
  guests without an account.
- **The operator** (the repository owner): runs the self-hosted server and
  moderates accounts from the admin screen.

## Product Purpose

rhythmo (ریتمو) is a private cloud music player. It
uploads, stores and streams a user's own music at original quality. It
merges cloud and on-device tracks into one library and plays them with
system media controls. Success is a library that is quick to fill and
pleasant to listen from, on a phone or in a browser.

## Positioning

A personal, self-hosted music locker built for Persian listeners. It keeps
original files untouched and plays only the user's own library. Imports
come from the messengers and sites they already use (Bale and Telegram bots,
song links). Lyrics come from LRCLIB, and song identification only matches
music already in rhythmo. It is not a streaming catalogue.

## Operating Context

- Mostly phones, often one-handed, often on slow or filtered connections
  *(inferred from short-lived stream links, offline cache and retry
  states)*; the web app runs on desktop browsers too.
- Listening continues in the background with the screen off, controlled
  from notifications and the lock screen.
- Music arrives from local files, multi-file uploads, the Bale and Telegram
  bots, links (including YouTube, Instagram and Spotify through the import
  service), shared playlists and identification.

## Capabilities and Constraints

- Library: upload with per-file progress, Android local-audio discovery,
  sync both ways, metadata editing that rewrites embedded tags, downloads
  under the edited filename.
- Playback: queue, shuffle, repeat, crossfade, speed, sleep timer, recently
  played, favourites, lyrics, «این آهنگ چیه؟» identification.
- Sharing: playlists by link, public playlists with likes, collaborative
  playlists with members.
- A server-enforced 1 GiB per-user quota, upload limits and rate limits.
- Original audio is never transcoded.
- Copy is Persian; layout is RTL.
- Supported clients are Web and Android only.

## Brand Commitments

- Name: **rhythmo** / **ریتمو**. The old name `sot` must not appear.
  `nafir` identifiers remain for compatibility.
- A polished, dark, glass-like look that never sacrifices contrast,
  legibility or performance (AGENTS.md).
- Bundled Vazirmatn type and Phosphor icons; nothing loads from a font or
  icon CDN at runtime.
- Voice *(inferred from existing copy)*: plain, friendly, informal Persian
  that names the problem and the way out.

## Evidence on Hand

- Store listing text, screenshots, teaser and graphics: `docs/store-listing.md`
  and `store/`.
- App icon: `assets/icon/rhythmo.png`.
- There are no testimonials, user counts or press; none should be invented.

## Product Principles

1. **The listener's music, untouched.** Quality, filenames and metadata stay
   as the user left them.
2. **Playback never waits on chrome.** Controls, the mini player and system
   insets never cover content or the next action.
3. **Every state says what to do next.** Empty, loading and failure states
   name the problem and the way out, in Persian.
4. **The same app everywhere.** Web and Android behave alike where the
   platform allows.

## Accessibility & Inclusion

- WCAG AA contrast for text, and at least 3:1 for interface marks.
- Touch targets of at least 48 px; safe-area awareness.
- Visible keyboard focus on the web.
- Reduce-motion is honoured.
- RTL first, with mixed Persian, Arabic and Latin text rendering correctly
  line by line.
