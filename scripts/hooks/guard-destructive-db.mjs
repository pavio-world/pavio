#!/usr/bin/env node
// Kiro PreToolUse hook for Supabase MCP tools.
// Blocks destructive branch and notebook tools outright, and blocks SQL that
// destroys data (drop table or schema, truncate, delete without where) in
// execute_sql or apply_migration. Exit 2 blocks the call and tells the agent why.

const BLOCKED_TOOLS = /(reset_branch|merge_branch|rebase_branch|delete_branch|delete_notebook|delete_feedback)/;
const DESTRUCTIVE_SQL = [
  /\bdrop\s+(table|schema|database|materialized\s+view|view|type)\b/i,
  /\btruncate\b/i,
  /\bdelete\s+from\s+[\w."]+\s*(;|$)/im, // delete without a where clause
  /\balter\s+table\s+[\w."]+\s+drop\s+column\b/i,
];

let raw = "";
process.stdin.on("data", (c) => (raw += c));
process.stdin.on("end", () => {
  let event = {};
  try { event = JSON.parse(raw || "{}"); } catch { process.exit(0); }
  const tool = String(event.tool_name ?? event.toolName ?? "");
  const input = JSON.stringify(event.tool_input ?? event.toolInput ?? {})
    .replace(/\\n/g, "\n");

  const deny = (why) => {
    process.stderr.write(
      `Blocked by Pavio safety rule: ${why} ` +
      "Destructive database actions need Dominic's explicit approval in chat (see .kiro/steering/supabase.md). " +
      "Stop and ask him, explaining exactly what would be removed.\n"
    );
    process.exit(2);
  };

  if (BLOCKED_TOOLS.test(tool)) deny(`the tool ${tool} can destroy or overwrite data.`);
  if (/(execute_sql|apply_migration)/.test(tool) || /"(query|sql)"\s*:/.test(input)) {
    for (const re of DESTRUCTIVE_SQL) {
      if (re.test(input)) deny("this SQL drops, truncates or deletes data.");
    }
  }
  process.exit(0);
});
