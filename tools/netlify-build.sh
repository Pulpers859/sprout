#!/usr/bin/env bash
#
# Build the Sprout web app for deployment.
#
# Two jobs, in this order:
#   1. Run the web test suite. A red suite fails the deploy, so a bad push
#      cannot reach the live site just because it reached `main`.
#   2. Generate `sprout-firebase-config.js` from the environment.
#
# The config is generated rather than committed because the repo's secret
# scanning blocks live Firebase values and `.gitignore` excludes both config
# files. Every visitor's browser receives these values anyway, but they stay
# out of git all the same.
#
# Accepts either SPROUT_FIREBASE_CONFIG_JSON (the whole config as one JSON
# object) or the six SPROUT_FIREBASE_* variables. The six win if both are set.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
web="$root/Sprout-html"

echo "==> Running the web test suite"
( cd "$web" && node --test ./*.test.mjs )

echo "==> Writing sprout-firebase-config.js"
# Node does the parsing, validating and quoting in one place. Earlier this
# shelled the values out through `eval`, which is both fragile and a way for a
# value to run as a command.
SPROUT_OUT="$web/sprout-firebase-config.js" node <<'JS'
const { writeFileSync } = require('node:fs');

const FIELDS = [
  ['apiKey', 'SPROUT_FIREBASE_API_KEY'],
  ['authDomain', 'SPROUT_FIREBASE_AUTH_DOMAIN'],
  ['projectId', 'SPROUT_FIREBASE_PROJECT_ID'],
  ['storageBucket', 'SPROUT_FIREBASE_STORAGE_BUCKET'],
  ['messagingSenderId', 'SPROUT_FIREBASE_MESSAGING_SENDER_ID'],
  ['appId', 'SPROUT_FIREBASE_APP_ID'],
];

/**
 * Accepts either strict JSON or the contents of `sprout-firebase-config.js`
 * pasted verbatim — `window.SPROUT_FIREBASE = { apiKey: "...", ... };`.
 *
 * That file is JavaScript, not JSON: its keys are unquoted. Requiring someone
 * to hand-convert it, on a phone, into a single-line JSON string is a good way
 * to get a deploy that fails on a typo. So the wrapper and the comments are
 * stripped and the known keys are quoted, then it is parsed as JSON.
 *
 * Deliberately not `eval` or `new Function`: this is a config value, and
 * nothing here needs the ability to run code.
 */
function parseConfigInput(raw) {
  try {
    return JSON.parse(raw);
  } catch {
    // Not strict JSON; fall through and try the JS-file shape.
  }

  const body = raw
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/^\s*\/\/.*$/gm, '');
  const open = body.indexOf('{');
  const close = body.lastIndexOf('}');
  if (open === -1 || close <= open) return null;

  const quoted = body
    .slice(open, close + 1)
    // Quote only the keys this config actually has, so nothing else in the
    // text can be reinterpreted as one.
    .replace(/([{,]\s*)(apiKey|authDomain|projectId|storageBucket|messagingSenderId|appId)(\s*:)/g, '$1"$2"$3')
    // A trailing comma is legal in JS and not in JSON.
    .replace(/,(\s*})/g, '$1');

  try {
    return JSON.parse(quoted);
  } catch {
    return null;
  }
}

let fromJson = {};
if (process.env.SPROUT_FIREBASE_CONFIG_JSON) {
  fromJson = parseConfigInput(process.env.SPROUT_FIREBASE_CONFIG_JSON);
  if (fromJson === null || typeof fromJson !== 'object' || Array.isArray(fromJson)) {
    console.error('SPROUT_FIREBASE_CONFIG_JSON could not be read.');
    console.error('Paste either a JSON object, or the whole contents of');
    console.error('sprout-firebase-config.js including the window.SPROUT_FIREBASE wrapper.');
    process.exit(1);
  }
}

const config = {};
const missing = [];
for (const [key, name] of FIELDS) {
  const value = process.env[name] || fromJson[key];
  if (typeof value !== 'string' || value === '') { missing.push(`${name} (or "${key}" in SPROUT_FIREBASE_CONFIG_JSON)`); continue; }
  config[key] = value;
}

if (missing.length) {
  console.error('Missing required Firebase config:');
  for (const name of missing) console.error(`  - ${name}`);
  console.error('Set them as repository secrets, or in Netlify under');
  console.error('Site configuration -> Environment variables.');
  console.error('Failing the build rather than publishing a site that cannot sign in.');
  process.exit(1);
}

writeFileSync(
  process.env.SPROUT_OUT,
  `// Generated at deploy time by tools/netlify-build.sh. Do not commit.\nwindow.SPROUT_FIREBASE = ${JSON.stringify(config, null, 2)};\n`
);
JS

echo "==> Done"
