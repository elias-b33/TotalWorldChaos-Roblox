#!/bin/bash
# SessionStart hook (see .claude/settings.json).
# In cloud sessions, if any Roblox tool is missing (for example because the
# environment has no setup script), install it in the background.
# Does nothing on your own computer.

[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0

missing=""
for tool in rojo stylua selene lune; do
	command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
done
[ -z "$missing" ] && exit 0

nohup bash "$CLAUDE_PROJECT_DIR/scripts/cloud-setup.sh" >/dev/null 2>&1 &
echo "Missing tools:$missing. Installing them in the background (several minutes); progress in /tmp/cloud-setup.log. Wait for 'cloud-setup: done' before running build or test commands."
exit 0
