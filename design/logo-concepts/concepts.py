"""Writes the #301 logo concepts as SVG: a full-colour app icon and a
one-colour glyph (for the Android notification icon) for each.

Run `python3 design/logo-concepts/concepts.py`, then
`node design/logo-concepts/render.mjs` for the PNG previews.
Colours are rhythmo's tokens (lib/core/design/tokens.dart).
"""
from pathlib import Path

HERE = Path(__file__).resolve().parent
PRIMARY = "#FF626A"  # NafirColors.primary (ember)
PRIMARY_DEEP = "#B72E50"  # NafirColors.primaryDeep
SECONDARY_DEEP = "#4E3B8D"  # NafirColors.secondaryDeep (violet)
ON_BRAND = "#FFF5F5"  # NafirColors.onBrand

GRADIENT = f"""  <defs>
    <linearGradient id="brand" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="{PRIMARY}"/>
      <stop offset="0.55" stop-color="{PRIMARY_DEEP}"/>
      <stop offset="1" stop-color="{SECONDARY_DEEP}"/>
    </linearGradient>
  </defs>
"""

# Each mark is drawn in a 512 box and keeps inside the maskable safe circle
# (centre 256,256, radius 204.8) so Android and PWA masks never clip it.
# Strokes are thick (>= 52 of 512, so >= 1.6 px at 16 px) and round-capped.
CONCEPTS = {
    "a-pulse-r": (
        "Pulse r",
        "A lowercase r whose arm becomes one heartbeat of rhythm.",
        '<path d="M176 372V252C176 216 202 194 238 194H252L290 124L334 280L360 206"'
        ' fill="none" stroke="{c}" stroke-width="56" stroke-linecap="round"'
        ' stroke-linejoin="round"/>',
    ),
    "b-wave-re": (
        "«ر» wave",
        "The Persian «ر» sweeping down from the right, led by three rising"
        " equaliser bars: rhythmo read right to left.",
        '<path d="M330 180C352 262 338 340 216 378" fill="none" stroke="{c}"'
        ' stroke-width="58" stroke-linecap="round"/>'
        '<rect x="132" y="250" width="40" height="72" rx="20" fill="{c}"/>'
        '<rect x="190" y="200" width="40" height="122" rx="20" fill="{c}"/>'
        '<rect x="248" y="152" width="40" height="120" rx="20" fill="{c}"/>',
    ),
    "c-beat-r": (
        "Beat r",
        "An r built from equaliser bars: a tall stem, a rounded arm, and"
        " one beat dot keeping time.",
        '<rect x="160" y="168" width="64" height="208" rx="32" fill="{c}"/>'
        '<path d="M192 248C192 204 226 172 270 172H290" fill="none"'
        ' stroke="{c}" stroke-width="64" stroke-linecap="round"/>'
        '<circle cx="342" cy="324" r="40" fill="{c}"/>',
    ),
}


def app_icon(mark: str) -> str:
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">\n'
        '  <title>rhythmo</title>\n'
        + GRADIENT
        + '  <rect width="512" height="512" fill="url(#brand)"/>\n'
        + "  " + mark.format(c=ON_BRAND) + "\n</svg>\n"
    )


def glyph(mark: str) -> str:
    # One colour on transparency, as Android tints notification icons.
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">\n'
        '  <title>rhythmo</title>\n'
        + "  " + mark.format(c="#FFFFFF") + "\n</svg>\n"
    )


if __name__ == "__main__":
    for name, (_, _, mark) in CONCEPTS.items():
        (HERE / f"{name}.svg").write_text(app_icon(mark))
        (HERE / f"{name}-mono.svg").write_text(glyph(mark))
    print("wrote", ", ".join(CONCEPTS))
