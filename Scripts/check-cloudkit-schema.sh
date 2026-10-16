#!/usr/bin/env bash
#
# Compares the CloudKit schema of the development environment with production, and lists what is in development and not yet
# in production: the record types and fields that a build from the App Store or TestFlight would not be able to sync.
#
#   Scripts/check-cloudkit-schema.sh                       reads both schemas with cktool
#   Scripts/check-cloudkit-schema.sh dev.ckdb prod.ckdb    compares two schema files already exported
#
# Why it exists: the app mirrors the person's data with SwiftData (ADR 0009, 0011). The first save of a new record type
# from a development build creates it in the *development* environment only. A TestFlight or App Store build uses
# *production*, where it does not exist until the schema is deployed in the CloudKit Dashboard ("Deploy Schema Changes...").
# Until then those records silently do not sync. Run this before a release that adds a model to the cloud container.
#
# cktool needs a CloudKit management token, made once at https://icloud.developer.apple.com (the team's account, "Tokens &
# Keys") and saved with:  xcrun cktool save-token --type management
# Exit status 1 when production lacks something, so it can gate a release.

set -euo pipefail

TEAM="${PANOP_TEAM:-4HUJUM5AUG}"
CONTAINER="${PANOP_CLOUDKIT_CONTAINER:-iCloud.com.panop.Panop}"

if [[ $# -eq 2 ]]; then
    dev="$1"
    prod="$2"
else
    work="$(mktemp -d -t panop-ckschema)"
    trap 'rm -rf "$work"' EXIT
    dev="$work/development.ckdb"
    prod="$work/production.ckdb"
    for environment in development production; do
        xcrun cktool export-schema --team-id "$TEAM" --container-id "$CONTAINER" --environment "$environment" \
            --output-file "$work/$environment.ckdb"
    done
fi

/usr/bin/python3 - "$dev" "$prod" <<'PY'
import re, sys

def parse(path):
    """{record type: {field: description}} from a .ckdb file."""
    types, current = {}, None
    for raw in open(path, encoding="utf-8"):
        line = raw.strip().rstrip(",")
        header = re.match(r"RECORD TYPE\s+(\S+)\s*\(", line)
        if header:
            current = types.setdefault(header.group(1).strip('"'), {})
            continue
        if line.startswith(");"):
            current = None
            continue
        if current is None or not line or line.startswith("GRANT") or line.startswith("--"):
            continue
        field = re.match(r'("?[\w$.]+"?)\s+(.*)$', line)
        if field:
            current[field.group(1).strip('"')] = field.group(2).strip()
    return types

dev, prod = parse(sys.argv[1]), parse(sys.argv[2])
# What Core Data keeps for itself (system fields and bookkeeping) is the same everywhere and is not news.
ignore = lambda name: name.startswith("___")
missing_types = sorted(t for t in dev if t not in prod)
differences = []
for name, fields in sorted(dev.items()):
    if name not in prod:
        continue
    for field, kind in sorted(fields.items()):
        if ignore(field):
            continue
        if field not in prod[name]:
            differences.append(f"  {name}.{field}  ({kind}) is not in production")
        elif prod[name][field] != kind:
            differences.append(f"  {name}.{field}: development has {kind!r}, production {prod[name][field]!r}")

print(f"development: {len(dev)} record types, production: {len(prod)}")
if not missing_types and not differences:
    print("Production has everything development has: nothing to deploy.")
    sys.exit(0)
if missing_types:
    print("\nRecord types in development and not in production:")
    for name in missing_types:
        print(f"  {name}  ({len([f for f in dev[name] if not ignore(f)])} fields)")
if differences:
    print("\nFields that differ:")
    print("\n".join(differences))
print("\nDeploy them: CloudKit Dashboard > the container > Schema > Deploy Schema Changes... (development to production).")
sys.exit(1)
PY
