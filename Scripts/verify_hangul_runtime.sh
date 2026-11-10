#!/usr/bin/env bash
# Finite macOS-only focused verification. No application/project source changes.
set -euo pipefail
ROOT=$(pwd)
H=$(mktemp -d /tmp/uniboard-hangul-runtime.XXXXXX)
trap 'rm -rf "$H"' EXIT
cp -R Shared "$H/Shared"
cp Package.swift "$H/Package.swift"
cp Keyboard/KeyboardLanguageCoordinator.swift Keyboard/KoreanHangulLanguageConverter.swift Keyboard/MandarinLanguageConverter.swift "$H/Shared/"
mkdir -p "$H/Tests/Fixtures"
cp Tests/KoreanHangulRuntimeTests.swift "$H/Tests/"
cp Scripts/verify_hangul_runtime_tests.swift "$H/Tests/HangulCoordinatorNativeTests.swift"
# Japanese engine's third-party dependency is unrelated to these Korean tests.
# A fail-fast compile-only stub is used; Japanese behavior is NOT tested.
cat > "$H/Shared/JapaneseCompileOnlyStub.swift" <<'SWIFT'
import Foundation
@MainActor final class JapaneseLanguageConverter: LanguageConversionEngine {
    let kanjiResourceStatus: LanguageConversionStatus = .failed
    init(installedDictionaryURL: URL, lease: LanguagePackReadLease, scratchDirectoryURL: URL) throws {
        fatalError("Japanese is outside this Korean-only harness")
    }
    func convert(_ request: LanguageConversionRequest) async throws -> LanguageConversionResult {
        fatalError("Japanese is outside this Korean-only harness")
    }
}
SWIFT
python3 - "$H/Package.swift" <<'PY'
import sys
p=sys.argv[1]
s=open(p).read().replace('sources: [', 'sources: ["KeyboardLanguageCoordinator.swift", "KoreanHangulLanguageConverter.swift", "MandarinLanguageConverter.swift", "JapaneseCompileOnlyStub.swift", ', 1)
open(p,'w').write(s)
PY
export HANGUL_FIXTURE_PATH="$ROOT/docs/language-resources/hangul-2set/1"
sw_vers
xcodebuild -version
swift --version
shasum -a 256 Keyboard/KeyboardLanguageCoordinator.swift Keyboard/KoreanHangulLanguageConverter.swift Shared/LanguageInputModePolicy.swift Tests/KoreanHangulRuntimeTests.swift Scripts/verify_hangul_runtime_tests.swift docs/language-resources/hangul-2set/1/hangul-2set.tar.gz
swift test --package-path "$H" --filter 'KoreanHangulRuntimeTests|HangulCoordinatorNativeTests'
echo HANGUL_RUNTIME_NATIVE_SUCCESS
