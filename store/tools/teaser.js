const { chromium } = require(require('child_process').execSync('npm root -g').toString().trim() + '/playwright');
const fs = require('fs');
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium', args: ['--no-sandbox'] });
  const p = await b.newPage({ viewport: { width: 1920, height: 1080 } });
  await p.goto('file://' + __dirname + '/teaser.html');
  await p.evaluate(() => document.fonts.ready);
  await p.waitForFunction(() => [...document.images].every(i => i.complete));
  const dur = await p.evaluate(() => window.DURATION);
  const fps = 30, n = Math.round(dur * fps);
  fs.mkdirSync(__dirname + '/frames', { recursive: true });
  const only = process.argv[2] ? process.argv[2].split(',').map(Number) : null;
  for (let i = 0; i < n; i++) {
    if (only && !only.includes(i)) continue;
    await p.evaluate(t => window.render(t), i / fps);
    await p.screenshot({ path: `${__dirname}/frames/f${String(i).padStart(4, '0')}.jpg`, type: 'jpeg', quality: 95 });
  }
  console.log('frames', n, 'duration', dur);
  await b.close();
})();
