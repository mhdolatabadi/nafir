const { chromium } = require(require('child_process').execSync('npm root -g').toString().trim() + '/playwright');
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });
  let p = await b.newPage({ viewport: { width: 1024, height: 500 } });
  await p.goto('file://' + __dirname + '/feature.html'); await p.evaluate(() => document.fonts.ready); await p.waitForTimeout(300);
  await p.screenshot({ path: __dirname + '/../listing/feature-graphic-1024x500.png' });
  p = await b.newPage({ viewport: { width: 512, height: 512 } });
  await p.goto('file://' + __dirname + '/icon.html');
  await p.screenshot({ path: __dirname + '/../listing/icon-512.png', omitBackground: true });
  await b.close();
})();
