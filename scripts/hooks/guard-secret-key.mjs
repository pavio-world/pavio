#!/usr/bin/env node
// Kiro PreToolUse hook: blocks writes that put the Supabase secret key
// (service role) anywhere except the allowed places.
// Exit 0 allows the tool call. Exit 2 blocks it and sends stderr to the agent.

// Paths where any mention of the secret key is allowed.
const ALLOWED = [
  /(^|\/)src\/lib\/supabase\/admin\.ts$/,
  /(^|\/)supabase\/seed\//,
  /(^|\/)\.env\.example$/,
  /(^|\/)\.kiro\//,
  /(^|\/)docs\//,
  /(^|\/)scripts\/hooks\//,
];

// SQL migrations and pgTAP tests must name the Postgres role service_role
// (grants, set local role, has_function_privilege). That word is a role name,
// not the key, and a .sql file cannot ship the key to a client bundle.
// These paths may contain the bare word, but nothing that looks like a real key.
// Paths that may name the service_role role (SQL grants, pgTAP tests,
// property tests that check service_role claims are rejected),
// but never contain anything that looks like the key itself.
const ROLE_NAME_OK = [
  /(^|\/)supabase\/migrations\/.+\.sql$/,
  /(^|\/)supabase\/tests\/.+\.sql$/,
  /(^|\/)tests\/property\/.+\.ts$/,
];

// Anything that mentions the key or the role.
const SECRET = /SUPABASE_SERVICE_ROLE_KEY|SUPABASE_SECRET_KEY|service_role|sb_secret_/;

// Anything that looks like the key itself or a variable holding it.
// Bare service_role is deliberately absent here.
const REAL_SECRET = new RegExp(
  [
    "SUPABASE_SERVICE_ROLE_KEY",
    "SUPABASE_SECRET_KEY",
    "sb_secret_",
    "service_role_key",
    "serviceRoleKey",
    // JWT: header.payload.signature, base64url, header starts with eyJ
    "eyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}",
  ].join("|"),
  "i"
);

let raw = "";
process.stdin.on("data", (c) => (raw += c));
process.stdin.on("end", () => {
  let event = {};
  try { event = JSON.parse(raw || "{}"); } catch { process.exit(0); }
  const input = JSON.stringify(event.tool_input ?? event.toolInput ?? {});
  if (!SECRET.test(input)) process.exit(0);

  const paths = [...input.matchAll(/"(?:path|file_path|filePath|target)"\s*:\s*"([^"]+)"/g)].map((m) => m[1]);
  if (paths.length === 0) block();

  const isAllowed = (p) => ALLOWED.some((re) => re.test(p));
  const isSqlRoleName = (p) => SQL_ROLE_NAME_OK.some((re) => re.test(p));

  if (paths.every(isAllowed)) process.exit(0);

  if (paths.every((p) => isAllowed(p) || isSqlRoleName(p))) {
    if (!REAL_SECRET.test(input)) process.exit(0);
    process.stderr.write(
      "Blocked by Pavio privacy rule: SQL migrations and tests may name the Postgres role " +
      "service_role, but this write contains something that looks like the secret key itself " +
      "(a JWT, sb_secret_, or a key variable name). Remove it.\n"
    );
    process.exit(2);
  }

  block();
});

function block() {
  process.stderr.write(
    "Blocked by Pavio privacy rule: the Supabase secret key bypasses Row Level Security. " +
    "It may only be used in src/lib/supabase/admin.ts or supabase/seed/. " +
    "SQL files under supabase/migrations/ and supabase/tests/ may name the service_role role, but never hold the key. " +
    "Create a Supabase client from the signed in user's session instead (see .kiro/steering/privacy.md).\n"
  );
  process.exit(2);
}