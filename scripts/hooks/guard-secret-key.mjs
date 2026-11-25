#!/usr/bin/env node
// Kiro PreToolUse hook: blocks writes that put the Supabase secret key
// (service role) anywhere except the two allowed places.
// Exit 0 allows the tool call. Exit 2 blocks it and sends stderr to the agent.

const ALLOWED = [
  /(^|\/)src\/lib\/supabase\/admin\.ts$/,
  /(^|\/)supabase\/seed\//,
  /(^|\/)\.env\.example$/,
  /(^|\/)\.kiro\//,
  /(^|\/)docs\//,
  /(^|\/)scripts\/hooks\//,
];
const SECRET = /SUPABASE_SERVICE_ROLE_KEY|SUPABASE_SECRET_KEY|service_role|sb_secret_/;

let raw = "";
process.stdin.on("data", (c) => (raw += c));
process.stdin.on("end", () => {
  let event = {};
  try { event = JSON.parse(raw || "{}"); } catch { process.exit(0); }
  const input = JSON.stringify(event.tool_input ?? event.toolInput ?? {});
  if (!SECRET.test(input)) process.exit(0);

  const paths = [...input.matchAll(/"(?:path|file_path|filePath|target)"\s*:\s*"([^"]+)"/g)].map((m) => m[1]);
  const allowed = paths.length > 0 && paths.every((p) => ALLOWED.some((re) => re.test(p)));
  if (allowed) process.exit(0);

  process.stderr.write(
    "Blocked by Pavio privacy rule: the Supabase secret key bypasses Row Level Security. " +
    "It may only be used in src/lib/supabase/admin.ts or supabase/seed/. " +
    "Create a Supabase client from the signed in user's session instead (see .kiro/steering/privacy.md).\n"
  );
  process.exit(2);
});
