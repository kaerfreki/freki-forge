#!/usr/bin/env bash
# Generate a bcrypt password hash for the Caddy reverse proxy (basic_auth).
#
# Usage:
#   ./scripts/gen-proxy-auth.sh                 # prompt (hidden)
#   ./scripts/gen-proxy-auth.sh 'my-password'   # non-interactive
#   PROXY_USER=alice ./scripts/gen-proxy-auth.sh
#
# Prints lines ready to paste into compose/proxy/.env (with $ escaped as $$
# for Docker Compose). Never commits a password — .env is gitignored.
#
# Requires: docker (uses the same pinned Caddy image as compose/proxy).
set -euo pipefail

CADDY_IMAGE="${CADDY_IMAGE:-caddy:2.11.4-alpine}"
PROXY_USER="${PROXY_USER:-freki}"

if [[ -n "${1:-}" ]]; then
	plaintext=$1
else
	if [[ ! -t 0 ]]; then
		echo "✗ no password on argv and stdin is not a TTY" >&2
		exit 1
	fi
	read -r -s -p "Password: " plaintext
	echo
	read -r -s -p "Confirm:  " confirm
	echo
	if [[ "$plaintext" != "$confirm" ]]; then
		echo "✗ passwords do not match" >&2
		exit 1
	fi
fi

if [[ -z "$plaintext" ]]; then
	echo "✗ empty password" >&2
	exit 1
fi

if ! command -v docker >/dev/null; then
	echo "✗ docker is required (caddy hash-password runs in a one-shot container)" >&2
	exit 1
fi

echo "→ hashing with ${CADDY_IMAGE} ..." >&2
hash=$(docker run --rm "$CADDY_IMAGE" caddy hash-password --plaintext "$plaintext")
# Docker Compose treats $VAR in .env / interpolation — double every $
escaped=${hash//\$/\$\$}

cat <<EOF

# Paste into compose/proxy/.env (or merge with your existing file):
PROXY_USER=${PROXY_USER}
PROXY_PASSWORD_HASH=${escaped}

# Raw bcrypt (for a hand-written Caddyfile snippet — do not put this form in .env):
# ${hash}
EOF
