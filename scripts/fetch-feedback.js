#!/usr/bin/env node
// Fetch beta feedback (screenshot + crash) from App Store Connect.
//
// Uses the same .p8 API key fastlane already has configured for uploads
// (read from ios-app/fastlane/.env). No additional auth needed.
//
// Usage:
//   node scripts/fetch-feedback.js                # last 50 of each kind
//   node scripts/fetch-feedback.js --build 7      # filter to a build number
//   node scripts/fetch-feedback.js --crashes      # crashes only
//   node scripts/fetch-feedback.js --screenshots  # screenshots only

const fs = require('fs');
const path = require('path');
const https = require('https');
const jwt = require(path.join(__dirname, '..', 'lambda-backend', 'node_modules', 'jsonwebtoken'));

const APP_ID = '6762150204'; // OMyDay
const ENV_PATH = path.join(__dirname, '..', 'ios-app', 'fastlane', '.env');

const env = fs.readFileSync(ENV_PATH, 'utf8')
  .split('\n')
  .filter((l) => l && !l.startsWith('#'))
  .reduce((acc, l) => {
    const idx = l.indexOf('=');
    if (idx > 0) acc[l.slice(0, idx).trim()] = l.slice(idx + 1).trim();
    return acc;
  }, {});

const KEY_ID = env.ASC_KEY_ID;
const ISSUER_ID = env.ASC_ISSUER_ID;
const KEY_PATH = env.ASC_KEY_PATH;
if (!KEY_ID || !ISSUER_ID || !KEY_PATH) {
  console.error('Missing ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH in', ENV_PATH);
  process.exit(1);
}

const privateKey = fs.readFileSync(KEY_PATH, 'utf8');
const token = jwt.sign(
  { iss: ISSUER_ID, exp: Math.floor(Date.now() / 1000) + 1200, aud: 'appstoreconnect-v1' },
  privateKey,
  { algorithm: 'ES256', header: { alg: 'ES256', kid: KEY_ID, typ: 'JWT' } }
);

const argv = process.argv.slice(2);
const buildFilter = argv.includes('--build') ? argv[argv.indexOf('--build') + 1] : null;
const onlyCrashes = argv.includes('--crashes');
const onlyScreenshots = argv.includes('--screenshots');

function get(urlPath) {
  return new Promise((resolve, reject) => {
    const req = https.request(
      {
        host: 'api.appstoreconnect.apple.com',
        path: urlPath,
        method: 'GET',
        headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' }
      },
      (res) => {
        let body = '';
        res.on('data', (chunk) => (body += chunk));
        res.on('end', () => {
          if (res.statusCode >= 200 && res.statusCode < 300) {
            try { resolve(JSON.parse(body)); } catch (e) { reject(e); }
          } else {
            reject(new Error(`HTTP ${res.statusCode}: ${body.slice(0, 300)}`));
          }
        });
      }
    );
    req.on('error', reject);
    req.end();
  });
}

function fmtDate(iso) { return iso ? iso.replace('T', ' ').replace(/\.\d+Z$/, ' UTC') : '—'; }

async function fetchScreenshots() {
  const includes = ['build', 'tester'];
  const path =
    `/v1/apps/${APP_ID}/betaFeedbackScreenshotSubmissions` +
    `?include=${includes.join(',')}` +
    `&fields[builds]=version,uploadedDate` +
    `&fields[betaTesters]=email,firstName,lastName` +
    `&sort=-createdDate&limit=50`;
  return await get(path);
}

async function fetchCrashes() {
  const includes = ['build', 'tester'];
  const path =
    `/v1/apps/${APP_ID}/betaFeedbackCrashSubmissions` +
    `?include=${includes.join(',')}` +
    `&fields[builds]=version,uploadedDate` +
    `&fields[betaTesters]=email,firstName,lastName` +
    `&sort=-createdDate&limit=50`;
  return await get(path);
}

function index(included) {
  const m = new Map();
  for (const i of included || []) m.set(`${i.type}:${i.id}`, i);
  return m;
}

function describeTester(rel, idx) {
  if (!rel?.tester?.data) return 'unknown tester';
  const t = idx.get(`betaTesters:${rel.tester.data.id}`);
  if (!t) return 'tester ' + rel.tester.data.id;
  const a = t.attributes;
  const name = [a?.firstName, a?.lastName].filter(Boolean).join(' ').trim();
  return name ? `${name} <${a?.email}>` : a?.email || rel.tester.data.id;
}

function describeBuild(rel, idx) {
  if (!rel?.build?.data) return '—';
  const b = idx.get(`builds:${rel.build.data.id}`);
  return b?.attributes?.version || rel.build.data.id;
}

function buildMatches(rel, idx, want) {
  if (!want) return true;
  return describeBuild(rel, idx) === want;
}

(async () => {
  if (!onlyCrashes) {
    console.log('=== Screenshot feedback ===');
    try {
      const data = await fetchScreenshots();
      const idx = index(data.included);
      const items = data.data || [];
      let printed = 0;
      for (const item of items) {
        if (!buildMatches(item.relationships, idx, buildFilter)) continue;
        printed++;
        console.log(`#${item.id}  build ${describeBuild(item.relationships, idx)}`);
        console.log(`  when:    ${fmtDate(item.attributes?.createdDate)}`);
        console.log(`  tester:  ${describeTester(item.relationships, idx)}`);
        if (item.attributes?.deviceModel) console.log(`  device:  ${item.attributes.deviceModel}, iOS ${item.attributes.osVersion}`);
        if (item.attributes?.appUpTimeInMilliseconds != null)
          console.log(`  uptime:  ${Math.round(item.attributes.appUpTimeInMilliseconds / 1000)}s`);
        if (item.attributes?.locale) console.log(`  locale:  ${item.attributes.locale}`);
        if (item.attributes?.comment) console.log(`  comment: ${item.attributes.comment.replace(/\n+/g, ' ')}`);
        const shots = item.relationships?.screenshots?.data || [];
        if (shots.length) console.log(`  shots:   ${shots.length} attached (URLs available via /betaScreenshots/{id})`);
        console.log('');
      }
      if (!printed) console.log('(no screenshot feedback' + (buildFilter ? ` for build ${buildFilter}` : '') + ')');
    } catch (e) {
      console.error('Screenshot fetch failed:', e.message);
    }
  }

  if (!onlyScreenshots) {
    console.log('=== Crash submissions ===');
    try {
      const data = await fetchCrashes();
      const idx = index(data.included);
      const items = data.data || [];
      let printed = 0;
      for (const item of items) {
        if (!buildMatches(item.relationships, idx, buildFilter)) continue;
        printed++;
        console.log(`#${item.id}  build ${describeBuild(item.relationships, idx)}`);
        console.log(`  when:    ${fmtDate(item.attributes?.createdDate)}`);
        console.log(`  tester:  ${describeTester(item.relationships, idx)}`);
        if (item.attributes?.deviceModel) console.log(`  device:  ${item.attributes.deviceModel}, iOS ${item.attributes.osVersion}`);
        if (item.attributes?.appUpTimeInMilliseconds != null)
          console.log(`  uptime:  ${Math.round(item.attributes.appUpTimeInMilliseconds / 1000)}s`);
        if (item.attributes?.comment) console.log(`  comment: ${item.attributes.comment.replace(/\n+/g, ' ')}`);
        if (item.attributes?.crashLogsUrl) console.log(`  log:     ${item.attributes.crashLogsUrl}`);
        console.log('');
      }
      if (!printed) console.log('(no crash submissions' + (buildFilter ? ` for build ${buildFilter}` : '') + ')');
    } catch (e) {
      console.error('Crash fetch failed:', e.message);
    }
  }
})();
