#!/usr/bin/env bash
# Kiro PostFileSave hook: runs the pgTAP privacy tests against the linked
# (remote) Supabase dev project whenever a migration or database test changes.
# It never pushes or resets anything; migrations are pushed deliberately by the agent.

if ! command -v supabase >/dev/null 2>&1; then
  echo "Supabase CLI not installed; skipping database tests."
  exit 0
fi

if [ ! -f supabase/.temp/project-ref ]; then
  echo "No linked Supabase project (run: supabase link); skipping database tests."
  exit 0
fi

# Warn if there are local migrations not yet pushed to the linked project.
if supabase migration list --linked 2>/dev/null | awk -F'|' 'NR>2 && $1 ~ /[0-9]/ && $2 !~ /[0-9]/ {found=1} END {exit !found}'; then
  echo "Note: some migrations are not pushed yet (run: supabase db push). Tests reflect the remote schema."
fi

echo "Running pgTAP tests on the linked dev project..."
supabase test db --linked
