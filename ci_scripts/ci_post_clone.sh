#!/bin/sh
set -eu

repository_path="${CI_PRIMARY_REPOSITORY_PATH:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
cd "$repository_path"

command -v python3 >/dev/null 2>&1 || {
    echo 'Uniboard requires Python 3 to generate its Unicode catalog.' >&2
    exit 1
}
command -v swift >/dev/null 2>&1 || {
    echo 'Uniboard requires the Xcode Swift toolchain.' >&2
    exit 1
}
test -f Uniboard.xcodeproj/project.pbxproj || {
    echo 'The committed Uniboard Xcode project is missing.' >&2
    exit 1
}
test -f Scripts/generate_unicode.py || {
    echo 'The Unicode catalog generator is missing.' >&2
    exit 1
}

echo 'Uniboard build prerequisites are ready. The pre-build script refreshes the Unicode draft.'
