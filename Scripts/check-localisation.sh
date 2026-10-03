#!/usr/bin/env bash
#
# Compare the strings the code asks for with the ones in Panop/Localizable.xcstrings.
#
#   Scripts/check-localisation.sh          list strings with no entry, and entries nothing uses
#   Scripts/check-localisation.sh --strict also exit 1 when anything is missing a German translation
#
# The compiler lists a literal given to Text, Label, Button and the like, and to String(localized:).
# The command-line build does not write them into the catalog (only Xcode does), so a new string is
# found here and added to the catalog by hand or by opening the project in Xcode. A string built any
# other way (a String variable given to Text) is not found at all: use String(localized:).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
SHARED_SPM="${PANOP_SPM:-$HOME/Library/Developer/Panop-SharedSPM}"
out="$(mktemp -d -t panop-loc)"
trap 'rm -rf "$out"' EXIT

xcodebuild -exportLocalizations -project Panop.xcodeproj -localizationPath "$out" -exportLanguage en \
    -clonedSourcePackagesDirPath "$SHARED_SPM" >/dev/null 2>&1

/usr/bin/python3 - "$out/en.xcloc/Localized Contents/en.xliff" "$ROOT/Panop/Localizable.xcstrings" "${1:-}" <<'PY'
import html, json, re, sys
xliff, catalog, mode = sys.argv[1:4]
used = {html.unescape(k) for k in re.findall(r'<trans-unit id="([^"]*)"', open(xliff).read())}
entries = json.load(open(catalog))["strings"]
missing = sorted(used - set(entries))
unused = sorted(set(entries) - used)
untranslated = sorted(k for k, v in entries.items() if "de" not in v.get("localizations", {}))
print(f"{len(used)} strings in the code, {len(entries)} in the catalog")
for title, keys in (("No entry in the catalog", missing), ("In the catalog, used by nothing", unused),
                    ("No German translation", untranslated)):
    if keys:
        print(f"\n{title} ({len(keys)}):")
        for key in keys:
            print("  " + repr(key))
sys.exit(1 if mode == "--strict" and (missing or untranslated) else 0)
PY
