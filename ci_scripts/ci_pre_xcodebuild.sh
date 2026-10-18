#!/bin/sh
set -eu

# A test-without-building action uses the catalog already embedded in the
# preceding build. Refresh immediately before actions that compile resources.
if [ "${CI_XCODEBUILD_ACTION:-build}" = 'test-without-building' ]; then
    exit 0
fi

repository_path="${CI_PRIMARY_REPOSITORY_PATH:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
cd "$repository_path"

python3 Scripts/validate_fonts.py

# This mode fetches fresh sources and fails on network or format errors; the
# build must never quietly continue using a stale cached draft.
python3 -m unittest discover -s Scripts/tests
ruby Scripts/tests/test_app_store_release.rb
python3 Scripts/generate_unicode.py --source all --refresh
swift test

test -s Shared/Resources/UnicodeCatalog.ucd
test -s Shared/Resources/Blocks.json
test -s Shared/Resources/UnicodeSources.json
test -s Shared/Resources/UnicodeProperties.json
test -s Shared/Resources/UnicodeCatalog-latest.ucd
test -s Shared/Resources/Blocks-latest.json
test -s Shared/Resources/UnicodeSources-latest.json
test -s Shared/Resources/UnicodeProperties-latest.json
test -s Shared/Resources/EmojiCatalog-draft.json
test -s Shared/Resources/EmojiCatalog-latest.json
echo 'Both Unicode editions and full emoji sequences passed validation and are ready to compile.'
