#!/bin/bash
set -euo pipefail
label="personal.AIUsageBar.login"
agent="$HOME/Library/LaunchAgents/$label.plist"
domain="gui/$(id -u)"
case "${1:-status}" in
  enable)
    test -x "$HOME/Applications/AI Usage.app/Contents/MacOS/AIUsageBar"
    mkdir -p "$HOME/Library/LaunchAgents"
    /usr/bin/python3 - "$agent" "$HOME/Applications/AI Usage.app" <<'PYTHON'
import plistlib,sys
from pathlib import Path
path=Path(sys.argv[1])
with path.open('wb') as f:
    plistlib.dump({'Label':'personal.AIUsageBar.login',
        'ProgramArguments':['/usr/bin/open','-g','-a',sys.argv[2],'--args','--background'],
        'RunAtLoad':True,'LimitLoadToSessionType':'Aqua'},f)
path.chmod(0o644)
PYTHON
    /bin/launchctl bootout "$domain/$label" 2>/dev/null || true
    /bin/launchctl enable "$domain/$label"
    /bin/launchctl bootstrap "$domain" "$agent"
    ;;
  disable)
    /bin/launchctl bootout "$domain/$label" 2>/dev/null || true
    # Keep the definition for easy re-enabling, but disable future login runs.
    /bin/launchctl disable "$domain/$label"
    ;;
  status)
    /bin/launchctl print "$domain/$label"
    /bin/launchctl print-disabled "$domain"
    ;;
  *) echo "Usage: bash Scripts/login-item.sh enable|disable|status" >&2; exit 2 ;;
esac
