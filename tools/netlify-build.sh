#!/usr/bin/env bash
#
# Netlify build for the Sprout web app.
#
# Two jobs, in this order:
#   1. Run the web test suite. A red suite fails the deploy, so a bad push
#      cannot reach the live site just because it reached `main`.
#   2. Generate `sprout-firebase-config.js` from environment variables.
#
# The config is generated rather than committed because the repo's secret
# scanning blocks live Firebase values and `.gitignore` excludes both config
# files. The values are public in the sense that every visitor's browser
# receives them, but they stay out of git all the same — set them in
# Netlify under Site configuration -> Environment variables.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
web="$root/Sprout-html"

echo "==> Running the web test suite"
( cd "$web" && node --test ./*.test.mjs )

echo "==> Writing sprout-firebase-config.js from the environment"
missing=()
for name in SPROUT_FIREBASE_API_KEY SPROUT_FIREBASE_AUTH_DOMAIN SPROUT_FIREBASE_PROJECT_ID \
            SPROUT_FIREBASE_STORAGE_BUCKET SPROUT_FIREBASE_MESSAGING_SENDER_ID SPROUT_FIREBASE_APP_ID; do
  if [ -z "${!name:-}" ]; then missing+=("$name"); fi
done

if [ ${#missing[@]} -gt 0 ]; then
  echo "Missing required environment variable(s): ${missing[*]}" >&2
  echo "Set them in Netlify under Site configuration -> Environment variables." >&2
  echo "Failing the build rather than publishing a site that cannot sign in." >&2
  exit 1
fi

# `node` does the quoting so a value containing a quote or backslash cannot
# break out of the generated literal.
SPROUT_OUT="$web/sprout-firebase-config.js" node <<'JS'
const { writeFileSync } = require('node:fs');
const config = {
  apiKey: process.env.SPROUT_FIREBASE_API_KEY,
  authDomain: process.env.SPROUT_FIREBASE_AUTH_DOMAIN,
  projectId: process.env.SPROUT_FIREBASE_PROJECT_ID,
  storageBucket: process.env.SPROUT_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: process.env.SPROUT_FIREBASE_MESSAGING_SENDER_ID,
  appId: process.env.SPROUT_FIREBASE_APP_ID,
};
writeFileSync(
  process.env.SPROUT_OUT,
  `// Generated at deploy time by tools/netlify-build.sh. Do not commit.\nwindow.SPROUT_FIREBASE = ${JSON.stringify(config, null, 2)};\n`
);
JS

echo "==> Done"
