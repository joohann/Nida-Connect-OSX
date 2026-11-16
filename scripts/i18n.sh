#!/usr/bin/env bash
# Lists missing keys per language compared to EN (the source).
#   scripts/i18n.sh            -> report for all languages
#   scripts/i18n.sh new de     -> creates de.lproj with all keys empty ("")
#   scripts/i18n.sh fill nl    -> adds only the missing keys, empty, to nl
set -euo pipefail
cd "$(dirname "$0")/.."
RES=Resources
SRC="$RES/en.lproj/Localizable.strings"

keys() { { grep -oE '^"[^"]+"' "$1" || true; } | tr -d '"' | sort -u; }
empty() { { grep -E '^"[^"]+"[[:space:]]*=[[:space:]]*""' "$1" || true; } | { grep -oE '^"[^"]+"' || true; } | tr -d '"' | sort -u; }

case "${1:-report}" in
  new)
    lang="${2:?language code missing, e.g. de}"
    dir="$RES/$lang.lproj"; [[ -e "$dir" ]] && { echo "$dir already exists"; exit 1; }
    mkdir -p "$dir"
    keys "$SRC" | sed 's/.*/"&" = "";/' > "$dir/Localizable.strings"
    echo "Created: $dir/Localizable.strings ($(keys "$SRC" | wc -l | tr -d ' ') empty keys)"
    ;;
  fill)
    lang="${2:?language code missing}"; f="$RES/$lang.lproj/Localizable.strings"
    comm -23 <(keys "$SRC") <(keys "$f") | sed 's/.*/"&" = "";/' >> "$f"
    echo "Missing keys added empty to $f"
    ;;
  report)
    status=0
    for f in "$RES"/*.lproj/Localizable.strings; do
      lang=$(basename "$(dirname "$f")" .lproj); [[ $lang == en ]] && continue
      missing=$(comm -23 <(keys "$SRC") <(keys "$f"))
      blank=$(empty "$f")
      extra=$(comm -13 <(keys "$SRC") <(keys "$f"))
      if [[ -z "$missing$blank$extra" ]]; then echo "[$lang] complete"; continue; fi
      status=1
      [[ -n $missing ]] && { echo "[$lang] missing:"; sed 's/^/  - /' <<<"$missing"; }
      [[ -n $blank ]]   && { echo "[$lang] empty (falls back to EN):"; sed 's/^/  - /' <<<"$blank"; }
      [[ -n $extra ]]   && { echo "[$lang] not in EN:"; sed 's/^/  - /' <<<"$extra"; }
    done
    exit $status
    ;;
  *) echo "Usage: $0 [report|new <lang>|fill <lang>]"; exit 2 ;;
esac
