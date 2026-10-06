# Store listing assets

Ready-to-upload graphics for Cafe Bazaar (and Google Play), made from the real app (#204).

| File | Size | Use |
|---|---|---|
| `listing/screenshot-1.png` … `screenshot-7.png` | 1080×1920 | Phone screenshots, in this order |
| `listing/rhythmo-teaser-1920x1080.mp4` | 1920×1080, 24 s, H.264 + AAC | Teaser video |
| `listing/feature-graphic-1024x500.png` | 1024×500 | Header / feature graphic |
| `listing/icon-512.png` | 512×512 | High-resolution icon |

The screenshots show the release web build, which looks the same as the Android app. The data in them is made up: no real artists, songs or album art appear, and the teaser's background audio is generated, so nothing needs a licence.

## Regenerating

Do this after UI changes. You need node with Playwright, Chromium and an ffmpeg with libx264 on `PATH`.

1. Build the web app with `flutter build web --release --base-href /app/`. Serve it, the API and MinIO behind one origin at `http://127.0.0.1:8443`, the way `deploy/Caddyfile` does.
2. Generate a few real MP3s and seed a fresh database:

   ```sh
   mkdir -p /tmp/audio
   for d in 192 245 213 278 201 236; do
     ffmpeg -f lavfi -i "aevalsrc='0.18*sin(2*PI*220*t)+0.12*sin(2*PI*277.18*t)+0.1*sin(2*PI*329.63*t)':s=44100:d=$d" -ac 2 -b:a 192k /tmp/audio/s$d.mp3
   done
   node store/tools/seed.mjs /tmp/audio /tmp/seed.json
   ```

3. Capture the app screens at 412×915 with 2.625× density (a common Android phone): `node store/tools/capture.js`.
4. Frame the screenshots and draw the graphics: `node store/tools/frames.js && node store/tools/misc.js`.
5. Render and encode the teaser: `store/tools/encode.sh`.

Headlines and captions live in `tools/frames.js` (screenshots) and `tools/teaser.html` (video).
