# rhythmo logo concepts (#301)

Three candidates to replace the current mark. Pick one and the derived
icons are regenerated from it (see #301); nothing in the app changes until
then.

| Concept | Idea | Files |
| --- | --- | --- |
| **A · Pulse r** | A lowercase r whose arm becomes one beat of a pulse. | `a-pulse-r.svg`, `a-pulse-r-mono.svg` |
| **B · «ر» wave** | The Persian «ر» sweeping down from the right, led by three rising equaliser bars: the name read right to left. | `b-wave-re.svg`, `b-wave-re-mono.svg` |
| **C · Beat r** | An r built from equaliser shapes, with one beat dot keeping time. The simplest, so the clearest at 16 px. | `c-beat-r.svg`, `c-beat-r-mono.svg` |

All three share the same rules:

- **Brand gradient**: ember `#FF626A` through `#B72E50` to violet `#4E3B8D`,
  under an `onBrand` `#FFF5F5` mark (tokens in
  `lib/core/design/tokens.dart`).
- **Safe zone**: each mark stays inside the maskable safe circle (radius 204.8
  of 512), so Android and PWA masks never clip it.
- **Small sizes**: strokes are at least 52/512 wide, so they stay at least
  1.6 px at 16 px.
- **Notification icon**: `*-mono.svg` is the same mark in one colour on
  transparency, as Android needs for its status-bar icon.

`*-preview.png` shows each concept at 512, 48, 24 and 16 px, masked round
and as a squircle, and as the monochrome icon on dark and light status
bars. `overview.png` shows all three together.

To regenerate:

```sh
python3 design/logo-concepts/concepts.py
NODE_PATH=$(npm root -g) node design/logo-concepts/render.mjs
```
