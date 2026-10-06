import fs from 'fs';
const base = 'http://127.0.0.1:8443/api/v1';
const files = fs.readdirSync(process.argv[2]).filter(f => f.endsWith('.mp3')).sort().map(f => fs.readFileSync(process.argv[2] + '/' + f));
let n = 0;
const j = async (path, opts = {}) => {
  const r = await fetch(base + path, { ...opts, headers: { 'Content-Type': 'application/json', ...(opts.headers || {}) } });
  const text = await r.text();
  if (!r.ok) throw new Error(path + ' ' + r.status + ' ' + text);
  return text ? JSON.parse(text) : {};
};
async function account(email) {
  let a;
  try { a = await j('/auth/register', { method: 'POST', body: JSON.stringify({ email, password: 'correct horse' }) }); }
  catch { a = await j('/auth/login', { method: 'POST', body: JSON.stringify({ email, password: 'correct horse' }) }); }
  return { Authorization: 'Bearer ' + (a.accessToken || a.token) };
}
async function upload(H, [title, artist, album]) {
  const audio = files[n++ % files.length];
  const created = await j('/tracks/uploads', { method: 'POST', headers: H, body: JSON.stringify({ fileName: title + '.mp3', sizeBytes: audio.length, title, artist, album }) });
  const form = new FormData();
  for (const [k, v] of Object.entries(created.upload.fields)) form.append(k, v);
  form.append('file', new Blob([audio], { type: 'audio/mpeg' }));
  const up = await fetch(created.upload.url, { method: 'POST', body: form });
  if (!up.ok) throw new Error('upload ' + up.status);
  await j(`/tracks/${created.track.id}/complete`, { method: 'POST', headers: H });
  return created.track.id;
}
// Made-up titles and artists only: store images must not show real artists.
const songs = [
  ['شب‌های تهران', 'آوا رادمهر', 'نور'],
  ['باران پاییزی', 'آوا رادمهر', 'نور'],
  ['Midnight Drive', 'Nova Lane', 'City Lights'],
  ['کوچه‌باغ', 'گروه سپیدار', 'سپیدار'],
  ['Golden Hour', 'Nova Lane', 'City Lights'],
  ['دریا', 'سینا مهرآیین', null],
  ['آسمان آبی', 'گروه سپیدار', 'سپیدار'],
  ['Slow Waves', 'Kai Morrow', 'Tides'],
  ['ستاره‌ی دنباله‌دار', 'سینا مهرآیین', null],
  ['Paper Planes', 'Kai Morrow', 'Tides'],
  ['ترانه‌ی صبح', 'آوا رادمهر', 'نور'],
  ['Northern Lights', 'Nova Lane', 'City Lights'],
];
const H = await account('sara@rhythmo.ir');
const ids = [];
for (const s of songs) ids.push(await upload(H, s));
const playlists = {};
for (const [name, pick, pub] of [
  ['آهنگ‌های جاده', [2, 4, 11, 0, 5], true],
  ['تمرکز و کار', [7, 9, 1, 6], false],
  ['صبح بخیر', [10, 3, 6, 8], true],
]) {
  const p = await j('/playlists', { method: 'POST', headers: H, body: JSON.stringify({ name }) });
  await j(`/playlists/${p.id}/tracks`, { method: 'PUT', headers: H, body: JSON.stringify({ trackIds: pick.map(i => ids[i]) }) });
  const shared = await j(`/playlists/${p.id}/share`, { method: 'POST', headers: H, body: JSON.stringify({ public: pub }) });
  playlists[name] = { id: p.id, token: shared.shareToken };
}
// Other listeners like the public ones, so the popular list has numbers.
const others = [];
for (let i = 1; i <= 6; i++) others.push(await account(`listener${i}@example.com`));
for (const [n, name] of [[6, 'آهنگ‌های جاده'], [3, 'صبح بخیر']]) {
  for (const O of others.slice(0, n)) await j(`/shared-playlists/${playlists[name].token}/like`, { method: 'PUT', headers: O });
}
// A public playlist from someone else too.
const O = others[0];
const oid = [];
for (const s of [['Ocean Breeze', 'Kai Morrow', 'Tides'], ['خاطره', 'سینا مهرآیین', null], ['Sunrise', 'Nova Lane', null]]) oid.push(await upload(O, s));
const op = await j('/playlists', { method: 'POST', headers: O, body: JSON.stringify({ name: 'آرامش شبانه' }) });
await j(`/playlists/${op.id}/tracks`, { method: 'PUT', headers: O, body: JSON.stringify({ trackIds: oid }) });
const os = await j(`/playlists/${op.id}/share`, { method: 'POST', headers: O, body: JSON.stringify({ public: true }) });
for (const X of others.slice(1, 5)) await j(`/shared-playlists/${os.shareToken}/like`, { method: 'PUT', headers: X });
// Recently played history.
for (const i of [2, 0, 5, 7]) await j('/history', { method: 'POST', headers: H, body: JSON.stringify({ trackId: ids[i] }) });
fs.writeFileSync(process.argv[3], JSON.stringify({ ids, playlists }, null, 2));
console.log('seeded', ids.length, 'tracks');
