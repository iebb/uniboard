#!/usr/bin/env bash
# Real adapters and upstream DictionaryMock, always Release (no typed-text DEBUG logs).
set -euo pipefail
ROOT=$(pwd)
H=$(mktemp -d /tmp/uniboard-conversion-runtime.XXXXXX)
trap 'rm -rf "$H"' EXIT
cp -R Shared "$H/Shared"
cp Package.swift "$H/Package.swift"
cp Keyboard/{KeyboardLanguageCoordinator,JapaneseLanguageConverter,MandarinLanguageConverter,KoreanHangulLanguageConverter}.swift "$H/Shared/"
mkdir -p "$H/Tests/Fixtures"
cp Scripts/verify_conversion_runtime_tests.swift "$H/Tests/ConversionRuntimeTests.swift"
python3 - "$H/Package.swift" "$ROOT" <<'PY'
import sys
p,root=sys.argv[1:]
s=open(p).read().replace('    targets: [', '    dependencies: [.package(path: "'+root+'/Vendor/AzooKeyKanaKanjiConverter")],\n    targets: [',1)
s=s.replace('.target(name: "UniboardCore", path:', '.target(name: "UniboardCore", dependencies: [.product(name: "KanaKanjiConverterModule", package: "AzooKeyKanaKanjiConverter")], path:',1)
s=s.replace('sources: [', 'sources: ["KeyboardLanguageCoordinator.swift", "JapaneseLanguageConverter.swift", "MandarinLanguageConverter.swift", "KoreanHangulLanguageConverter.swift", ',1)
open(p,'w').write(s)
PY
export CONVERSION_DICTIONARY_MOCK="$ROOT/Vendor/AzooKeyKanaKanjiConverter/Tests/KanaKanjiConverterModuleTests/DictionaryMock"
sw_vers
xcodebuild -version
swift --version
shasum -a 256 Keyboard/{JapaneseLanguageConverter,MandarinLanguageConverter,KeyboardLanguageCoordinator,KeyboardViewController}.swift Scripts/verify_conversion_runtime_tests.swift
if [[ "${CONVERSION_ASYNC:-0}" == 1 ]]; then
  # Assert actual execution context in copied real adapters, including Release.
  python3 - "$H" <<'PY'
import sys
for name in ["JapaneseLanguageConverter", "MandarinLanguageConverter"]:
    p=sys.argv[1]+"/Shared/"+name+".swift"
    s=open(p).read().replace("async throws -> LanguageConversionResult {", 'async throws -> LanguageConversionResult {\n        precondition(!Thread.isMainThread, "Conversion executed on main thread")', 1)
    open(p,"w").write(s)
PY
  swift test -c release --package-path "$H" -Xswiftc -DASYNC_CONVERSION --filter ConversionRuntimeTests
else
  swift test -c release --package-path "$H" --filter ConversionRuntimeTests
fi
echo CONVERSION_RUNTIME_RELEASE_SUCCESS
