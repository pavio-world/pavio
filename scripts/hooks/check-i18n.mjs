#!/usr/bin/env node
// Kiro PostFileSave hook: English and Swahili string files must have exactly
// the same keys. String files use flat quoted keys, e.g. "profile.connect": "Connect".
import { readFileSync, existsSync } from "node:fs";

const files = { en: "src/config/strings/en.ts", sw: "src/config/strings/sw.ts" };
if (!existsSync(files.en) || !existsSync(files.sw)) process.exit(0);

const keys = (f) => new Set([...readFileSync(f, "utf8").matchAll(/"([^"]+)"\s*:/g)].map((m) => m[1]));
const en = keys(files.en);
const sw = keys(files.sw);
const missingSw = [...en].filter((k) => !sw.has(k));
const missingEn = [...sw].filter((k) => !en.has(k));

if (missingSw.length || missingEn.length) {
  if (missingSw.length) console.error(`Missing in Swahili (sw.ts): ${missingSw.join(", ")}`);
  if (missingEn.length) console.error(`Missing in English (en.ts): ${missingEn.join(", ")}`);
  process.exit(1);
}
console.log(`Strings in sync: ${en.size} keys in English and Swahili.`);
