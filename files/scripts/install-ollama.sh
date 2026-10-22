#!/usr/bin/env bash
# Runs at image BUILD time (not on users' machines).
# Installs Ollama into /usr from a pinned, checksum-verified release file.
set -oue pipefail

# Pinned version — confirmed in Step 1 of RABBIT-BLUEPRINT.md. Never use "latest".
OLLAMA_VERSION="v0.40.6"
OLLAMA_FILE="ollama-linux-amd64.tar.zst"
BASE_URL="https://github.com/ollama/ollama/releases/download/${OLLAMA_VERSION}"

# zstd is needed to extract the .tar.zst release file (install it if missing).
command -v zstd || dnf install -y zstd

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT  # deletes the temp folder on exit, success or failure

echo "Downloading Ollama ${OLLAMA_VERSION} (${OLLAMA_FILE}) ..."
curl -fL -o "${TMP_DIR}/${OLLAMA_FILE}" "${BASE_URL}/${OLLAMA_FILE}"
curl -fL -o "${TMP_DIR}/sha256sum.txt" "${BASE_URL}/sha256sum.txt"

# Security check: verify the download against the official sha256sum.txt.
# The txt lists every release asset; its lines look like "<hash>  ./ollama-linux-amd64.tar.zst",
# so allow an optional "./" prefix and match the exact file name (dots escaped).
grep -E "^[0-9a-fA-F]{64}[[:space:]]+(\./)?ollama-linux-amd64\.tar\.zst\$" "${TMP_DIR}/sha256sum.txt" > "${TMP_DIR}/expected.sha256"
if [ "$(wc -l < "${TMP_DIR}/expected.sha256")" -ne 1 ]; then
    echo "ERROR: expected exactly one sha256 line for ${OLLAMA_FILE} — refusing to install an unverified download." >&2
    exit 1
fi
( cd "${TMP_DIR}" && sha256sum --check expected.sha256 )

echo "Checksum verified. Extracting into /usr ..."
tar --zstd -xf "${TMP_DIR}/${OLLAMA_FILE}" -C /usr

# Prove the binary runs (blueprint: print 'ollama --version'; fall back if it needs a server).
if ! /usr/bin/ollama --version; then
    echo "'ollama --version' did not succeed (no server running?) — proving the binary runs instead:" >&2
    /usr/bin/ollama -v || { /usr/bin/ollama --help | head -1; }
fi

echo "Ollama ${OLLAMA_VERSION} installed: /usr/bin/ollama"