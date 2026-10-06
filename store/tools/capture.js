const c = require('./common.js');
const out = process.argv[2] || __dirname + '/raw';
require('fs').mkdirSync(out, { recursive: true });
const shot = async (page, name) => { await page.mouse.move(1, 450); await page.waitForTimeout(1200); await page.screenshot({ path: `${out}/${name}.png` }); };
(async () => {
  const { browser, page } = await c.open();
  await shot(page, '06-guest');
  await c.login(page);
  await c.tapHas(page, 'Northern Lights');
  await page.waitForTimeout(3000);
  await shot(page, '01-library');
  // Now playing: tap the mini player.
  await page.mouse.click(283, 869);
  await page.waitForTimeout(2500);
  await shot(page, '02-now-playing');
  await page.mouse.click(48, 31);
  await page.waitForTimeout(1500);
  await shot(page, '08-sleep-timer');
  await page.keyboard.press('Escape'); await page.waitForTimeout(800);
  await page.goBack(); await page.waitForTimeout(1500);
  await c.tap(page, 'فهرست‌های پخش');
  await page.waitForTimeout(1500);
  await shot(page, '03-playlists');
  await c.tapHas(page, 'آهنگ‌های جاده');
  await page.waitForTimeout(2000);
  await shot(page, '04-playlist');
  await page.goBack(); await page.waitForTimeout(1500);
  await c.tap(page, 'آهنگ‌ها');
  await page.waitForTimeout(1000);
  // Search from the top bar.
  await page.mouse.click(80, 28);
  await page.waitForTimeout(1500);
  await page.keyboard.type('Nova', { delay: 80 });
  await page.waitForTimeout(1500);
  await page.keyboard.press('Escape').catch(() => {});
  await shot(page, '05-search');
  await browser.close();
})();
