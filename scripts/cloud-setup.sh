#!/bin/bash
# Installs the Roblox toolchain for Claude Code cloud sessions:
#   rojo (build the place), stylua (format), selene (lint), lune (run Luau tests)
#
# Paste this whole file into the cloud environment's "Setup script" box.
# It is also safe to run by hand: bash scripts/cloud-setup.sh
#
# Why not GitHub release downloads? Cloud sessions can only reach GitHub repos
# attached to the session, so other projects' release binaries are blocked.
# StyLua ships prebuilt on npm; the rest compile from crates.io. Debug builds
# compile several times faster and run fast enough for a project this size.

set -uo pipefail
LOG=/tmp/cloud-setup.log
BIN=/usr/local/bin
export PATH="$HOME/.cargo/bin:$PATH"
export CARGO_TERM_PROGRESS_WHEN=never
export CARGO_NET_RETRY=5

has() { command -v "$1" >/dev/null 2>&1; }
start=$(date +%s)
echo "cloud-setup: starting" | tee -a "$LOG"

# StyLua: prebuilt binary from npm (seconds)
if ! has stylua; then
	npm install -g @johnnymorganz/stylua-bin@2.6.0 >>"$LOG" 2>&1 || echo "cloud-setup: stylua install failed" | tee -a "$LOG"
fi

# Rojo, Selene, Lune: compiled from crates.io in parallel
build() {
	local name="$1"
	shift
	if has "$name"; then return 0; fi
	if cargo install --locked --debug "$@" >>"$LOG" 2>&1; then
		ln -sf "$HOME/.cargo/bin/$name" "$BIN/$name"
	else
		echo "cloud-setup: $name build failed (see $LOG)" | tee -a "$LOG"
	fi
}

build rojo rojo --version 7.7.1 &
build selene selene --version 0.31.0 &
build lune lune --version 0.11.1 --no-default-features --features cli,std-fs,std-process,std-stdio,std-task &
wait

for tool in rojo stylua selene lune; do
	if has "$tool"; then
		echo "cloud-setup: $tool $("$tool" --version 2>/dev/null | head -1)" | tee -a "$LOG"
	else
		echo "cloud-setup: $tool MISSING" | tee -a "$LOG"
	fi
done
echo "cloud-setup: done in $(($(date +%s) - start)) s" | tee -a "$LOG"

# Never block the session from starting; Claude can rerun this script if a tool is missing.
exit 0
