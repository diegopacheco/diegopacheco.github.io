#!/bin/bash
set -euo pipefail

BASE="${LAZYVIM_BASE:-https://diegopacheco.github.io/lazyvim/config}"
TARGET="$HOME/.config/nvim"
FILES="init.lua
lazyvim.json
lazy-lock.json
stylua.toml
lua/neotest_node.lua
lua/config/autocmds.lua
lua/config/keymaps.lua
lua/config/lazy.lua
lua/config/options.lua
lua/plugins/diagnostics.lua
lua/plugins/markdown.lua
lua/plugins/python.lua
lua/plugins/rust.lua
lua/plugins/test.lua"

if ! command -v nvim >/dev/null; then
  echo "Neovim is missing. Run: brew install neovim"
  exit 1
fi

STAGE="$(mktemp -d)"
for file in $FILES; do
  mkdir -p "$STAGE/$(dirname "$file")"
  curl -fsSL "$BASE/$file" -o "$STAGE/$file"
  echo "fetched $file"
done

if [ -e "$TARGET" ]; then
  BACKUP="$TARGET.bak.$(date +%Y%m%d%H%M%S)"
  mv "$TARGET" "$BACKUP"
  echo "Your previous config is now at $BACKUP"
fi

mkdir -p "$(dirname "$TARGET")"
mv "$STAGE" "$TARGET"
echo "Installed to $TARGET. Run nvim, lazy.nvim installs every plugin on first launch."
