// Renders preview PNGs of each #301 concept with the preinstalled Chromium:
// the app icon at 512/48/24/16 px, masked as a launcher icon, and the
// one-colour glyph on dark and light status bars.
// Run `NODE_PATH=$(npm root -g) node design/logo-concepts/render.mjs`.
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// Playwright is installed globally, which ES imports don't search.
const { chromium } = createRequire(import.meta.url)('playwright');

const here = dirname(fileURLToPath(import.meta.url));
const concepts = [
  ['a-pulse-r', 'A · Pulse r'],
  ['b-wave-re', 'B · «ر» wave'],
  ['c-beat-r', 'C · Beat r'],
];
const uri = (file) =>
  'data:image/svg+xml;base64,' +
  Buffer.from(readFileSync(join(here, file))).toString('base64');

function sheet([name, title]) {
  const icon = uri(`${name}.svg`);
  const mono = uri(`${name}-mono.svg`);
  const sizes = [48, 24, 16]
    .map((s) => `<figure><img src="${icon}" width="${s}" height="${s}"
      style="border-radius:${s * 0.22}px"><figcaption>${s}</figcaption></figure>`)
    .join('');
  const bar = (bg, fg) => `<div class="bar" style="background:${bg}">
      ${[24, 16].map((s) => `<span style="width:${s}px;height:${s}px;
        background:${fg};-webkit-mask:url(${mono}) center/contain no-repeat"></span>`).join('')}
      <b style="color:${fg}">ریتمو · در حال پخش</b></div>`;
  return `<section>
    <h2>${title}</h2>
    <div class="row">
      <img src="${icon}" width="256" height="256" style="border-radius:56px">
      <div class="col">
        <div class="row">${sizes}</div>
        <div class="row">
          <img src="${icon}" width="96" height="96" style="border-radius:50%">
          <img src="${icon}" width="96" height="96" style="border-radius:28px">
        </div>
        ${bar('#0B0D16', '#FFFFFF')}
        ${bar('#F4F1F5', '#1B1B22')}
      </div>
    </div>
  </section>`;
}

const style = `<style>
  body{margin:0;padding:24px;background:#070810;color:#F5F1F7;
    font-family:Vazirmatn,system-ui,sans-serif}
  section{padding:16px 0}
  h2{margin:0 0 12px;font-size:20px}
  .row{display:flex;gap:20px;align-items:center}
  .col{display:flex;flex-direction:column;gap:16px}
  figure{margin:0;text-align:center;color:#D0C8D4;font-size:12px}
  .bar{display:flex;gap:10px;align-items:center;padding:8px 14px;
    border-radius:12px;width:300px}
  .bar b{font-size:13px;font-weight:600}
</style>`;

const browser = await chromium.launch({
  executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome',
});
const page = await browser.newPage({ deviceScaleFactor: 1 });
for (const concept of concepts) {
  await page.setContent(`<html dir="ltr">${style}<body>${sheet(concept)}</body></html>`);
  await page.setViewportSize({ width: 680, height: 340 });
  await page.screenshot({ path: join(here, `${concept[0]}-preview.png`), fullPage: true });
}
await page.setContent(`<html>${style}<body>${concepts.map(sheet).join('')}</body></html>`);
await page.setViewportSize({ width: 680, height: 400 });
await page.screenshot({ path: join(here, 'overview.png'), fullPage: true });
await browser.close();
