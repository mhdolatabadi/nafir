const { chromium } = require(require('child_process').execSync('npm root -g').toString().trim() + '/playwright');
exports.open = async function (opts = {}) {
  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium', args: ['--no-sandbox', '--autoplay-policy=no-user-gesture-required'] });
  const page = await browser.newPage({ viewport: { width: 412, height: 915 }, deviceScaleFactor: 2.625, locale: 'fa-IR', ...opts });
  await page.route('**/*', r => new URL(r.request().url()).hostname === '127.0.0.1' ? r.continue() : r.abort());
  await page.goto('http://127.0.0.1:8443/app/');
  await page.waitForFunction(() => document.querySelector('flutter-view') && !document.getElementById('splash'), null, { timeout: 60000 });
  await page.waitForTimeout(1500);
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await page.waitForTimeout(800);
  return { browser, page };
};
exports.login = async function (page) {
  await exports.tap(page, 'ورود / ثبت‌نام');
  await page.waitForTimeout(1500);
  for (let attempt = 0; attempt < 3; attempt++) {
    const email = page.locator('input:not([type=password])').first();
    const pass = page.locator('input[type=password]').first();
    await email.click({ force: true }); await email.fill('sara@rhythmo.ir');
    await page.waitForTimeout(300);
    await pass.click({ force: true }); await pass.fill('correct horse');
    await page.waitForTimeout(300);
    if ((await email.inputValue()) === 'sara@rhythmo.ir' && (await pass.inputValue()) === 'correct horse') break;
  }
  await page.locator('input[type=password]').first().focus();
  await page.keyboard.press('Enter');
  await page.waitForTimeout(4000);
};
exports.labels = page => page.evaluate(() => [...document.querySelectorAll('flt-semantics [aria-label], flt-semantics')].map(e => (e.getAttribute('aria-label') || '').trim() + (e.getAttribute('role') ? ' <' + e.getAttribute('role') + '>' : '')).filter(s => s.length > 1));

// Taps a Flutter semantics node by its text or label; Playwright's own click
// refuses because Flutter positions those nodes with transforms.
exports.tap = async function (page, text, nth = 0) {
  for (let i = 0; i < 30; i++) {
    const found = await page.evaluate(t => [...document.querySelectorAll('flt-semantics')].some(e => (e.getAttribute('aria-label') || '') === t || e.textContent.trim() === t), text);
    if (found) break;
    await page.waitForTimeout(500);
  }
  const ok = await page.evaluate(([text, nth]) => {
    const all = [...document.querySelectorAll('flt-semantics')].filter(e =>
      (e.getAttribute('aria-label') || '') === text || e.textContent.trim() === text);
    const el = all[nth];
    if (!el) return false;
    el.click();
    return true;
  }, [text, nth]);
  if (!ok) throw new Error('no node ' + text);
  await page.waitForTimeout(1200);
};
// Taps the first semantics node whose label contains text.
exports.tapHas = async function (page, text, nth = 0) {
  for (let i = 0; i < 30; i++) {
    const found = await page.evaluate(t => [...document.querySelectorAll('flt-semantics')].some(e => (e.getAttribute('aria-label') || '').includes(t) || (e.children.length === 0 && e.textContent.includes(t))), text);
    if (found) break;
    await page.waitForTimeout(500);
  }
  const ok = await page.evaluate(([text, nth]) => {
    const all = [...document.querySelectorAll('flt-semantics')].filter(e =>
      (e.getAttribute('aria-label') || '').includes(text) || (e.children.length === 0 && e.textContent.includes(text)));
    const el = all[nth];
    if (!el) return false;
    el.click();
    return true;
  }, [text, nth]);
  if (!ok) throw new Error('no node containing ' + text);
  await page.waitForTimeout(1200);
};
