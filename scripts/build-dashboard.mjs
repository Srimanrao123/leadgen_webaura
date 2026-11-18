// Builds the hosted dashboard (Vercel, Netlify, any static host) into ./public/index.html.
// Reads SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY from the host's environment variables,
// or from .env when run locally:  node scripts/build-dashboard.mjs
// Only the publishable key is ever used. The build refuses secret / service_role keys.
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");

// Local convenience: fall back to .env when the variables aren't set.
const envFile = join(root, ".env");
if (existsSync(envFile)) {
  for (const line of readFileSync(envFile, "utf8").split("\n")) {
    const m = line.match(/^\s*([A-Z_]+)\s*=\s*(.*)\s*$/);
    if (m && !process.env[m[1]]) process.env[m[1]] = m[2].replace(/^["']|["']$/g, "");
  }
}

const url = (process.env.SUPABASE_URL || "").trim().replace(/\/+$/, "");
const key = (process.env.SUPABASE_PUBLISHABLE_KEY || "").trim();
const fail = (msg) => { console.error(`\n✖ ${msg}\n`); process.exit(1); };

if (!url || !key) fail("Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY (Vercel → Project → Settings → Environment Variables).");
if (!/^https:\/\/[a-z0-9-]+\.supabase\.(co|in)$/.test(url)) fail(`SUPABASE_URL should look like https://abcd1234.supabase.co (got "${url}").`);
if (/service_role|sb_secret_/.test(key)) fail("SUPABASE_PUBLISHABLE_KEY is a SECRET key. Use the publishable (anon) key. Remove the secret one from the host now.");
if (!/^sb_publishable_/.test(key)) {
  // Legacy anon keys are JWTs. Make sure the role inside is "anon".
  try {
    const payload = JSON.parse(Buffer.from(key.split(".")[1], "base64url").toString());
    if (payload.role !== "anon") fail(`This key's role is "${payload.role}". Use the publishable / anon key.`);
  } catch { fail("SUPABASE_PUBLISHABLE_KEY doesn't look like a publishable (sb_publishable_…) or anon key."); }
}

let html = readFileSync(join(root, "dashboard", "index.html"), "utf8");
const quotes = JSON.parse(readFileSync(join(root, "dashboard", "quotes.json"), "utf8"));
const cfgRe = /\/\*CONFIG\*\/[\s\S]*?\/\*END CONFIG\*\//, qRe = /\/\*QUOTES\*\/[\s\S]*?\/\*END QUOTES\*\//;
if (!cfgRe.test(html) || !qRe.test(html)) fail("dashboard/index.html is missing its CONFIG or QUOTES block.");
html = html.replace(cfgRe, () => `/*CONFIG*/const CONFIG = ${JSON.stringify({ url, key })};/*END CONFIG*/`)
           .replace(qRe, () => `/*QUOTES*/const QUOTES = ${JSON.stringify(quotes)};/*END QUOTES*/`);

mkdirSync(join(root, "public"), { recursive: true });
writeFileSync(join(root, "public", "index.html"), html);
console.log(`✔ Built public/index.html for ${url.replace(/^https:\/\/(.{4}).*?\./, "https://$1….")} with ${quotes.length} quotes`);
