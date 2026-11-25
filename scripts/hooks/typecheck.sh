#!/usr/bin/env bash
# Kiro PostFileSave hook: type checks the project after TypeScript changes.
[ -f tsconfig.json ] || exit 0
[ -d node_modules ] || exit 0
npx tsc --noEmit -p . 2>&1 | tail -25
exit "${PIPESTATUS[0]}"
