#!/bin/bash
# Installs this folder as a Claude skill and prepares the CRM settings.
# Usage:  ./install.sh          (links ~/.claude/skills/lead-outreach -> this folder; edits here apply instantly)
#         ./install.sh --copy   (copies instead of linking, if your setup doesn't follow links)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$HOME/.claude/skills/lead-outreach"
mkdir -p "$HOME/.claude/skills"

if [ -L "$TARGET" ]; then
  rm "$TARGET"
elif [ -e "$TARGET" ]; then
  BACKUP="$TARGET.backup-$(date +%Y%m%d-%H%M%S)"
  echo "Existing skill folder moved to $BACKUP"
  mv "$TARGET" "$BACKUP"
fi

if [ "${1:-}" = "--copy" ]; then
  rsync -a --exclude .git --exclude .env "$HERE/" "$TARGET/"
  [ -f "$HERE/.env" ] && cp "$HERE/.env" "$TARGET/.env"
  echo "Copied skill to $TARGET (re-run after every update)."
else
  ln -s "$HERE" "$TARGET"
  echo "Linked $TARGET -> $HERE"
fi

if [ ! -f "$HERE/.env" ]; then
  cp "$HERE/.env.example" "$HERE/.env"
  echo "Created .env. Open it and fill in SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY and CRM_EMAIL."
fi

python3 -c "import openpyxl" 2>/dev/null || pip3 install --quiet openpyxl || echo "Could not install openpyxl. Run: pip3 install openpyxl"

cat <<EOF

Next:
  1. Fill in .env (if you haven't).
  2. python3 "$HERE/scripts/crm.py" login
  3. python3 "$HERE/scripts/crm.py" dashboard --open
  4. Restart the Claude app.
EOF
