#!/bin/sh
set -eu

# A test-without-building action uses the catalog already embedded in the
# preceding build. Refresh immediately before actions that compile resources.
if [ "${CI_XCODEBUILD_ACTION:-build}" = 'test-without-building' ]; then
    exit 0
fi

repository_path="${CI_PRIMARY_REPOSITORY_PATH:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
cd "$repository_path"

# This mode fetches fresh sources and fails on network or format errors; the
# build must never quietly continue using a stale cached draft.
python3 -m unittest discover -s Scripts/tests
python3 Scripts/generate_unicode.py --source draft --refresh
swift test

test -s Shared/Resources/UnicodeCatalog.ucd
test -s Shared/Resources/Blocks.json
test -s Shared/Resources/UnicodeSources.json
echo 'The latest Unicode draft catalog passed validation and is ready to compile.'
