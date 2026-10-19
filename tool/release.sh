#!/usr/bin/env bash
# Builds a signed release APK and publishes it as a GitHub release.
#
#   tool/release.sh [release-notes/<version>.md]
#
# Reads the version from pubspec.yaml (`version: 1.2.0+5`), so bump that
# first. Refuses to continue if the APK isn't signed with your release key.
# With the GitHub CLI (`gh`, logged in) it creates the release; without it,
# it prints exactly what to upload. Then announce it from the official chat
# (Announce an app update → Fill from the latest GitHub release).
set -euo pipefail
cd "$(dirname "$0")/.."

NOTES_FILE="${1:-}"
VERSION_LINE=$(grep -E '^version:' pubspec.yaml | head -1 | awk '{print $2}')
NAME="${VERSION_LINE%%+*}"
CODE="${VERSION_LINE##*+}"
if [[ -z "$NAME" || -z "$CODE" || "$NAME" == "$CODE" ]]; then
  echo "pubspec.yaml version must look like 1.2.0+5 (name+code)." >&2
  exit 1
fi
TAG="v${NAME}+${CODE}"

if [[ ! -f android/key.properties ]]; then
  echo "android/key.properties is missing: the release would be signed with" >&2
  echo "the debug key and could never update existing installs." >&2
  exit 1
fi

DEFINES=()
[[ -f .env ]] && DEFINES=(--dart-define-from-file=.env)

APKSIGNER=$(find "${ANDROID_HOME:-$HOME/Android/Sdk}/build-tools" -name apksigner -type f 2>/dev/null | sort -V | tail -1)
REPO=$(git remote get-url origin | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')
TAG_URL=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$TAG")
mkdir -p build/release

# One APK for both 64-bit and 32-bit ARM phones (no x86: no real phones need
# it). A single file means nobody can download the wrong one.
FILES=()
echo "==> Building Serafim $NAME (code $CODE) for arm64-v8a + armeabi-v7a"
flutter build apk --release --target-platform android-arm,android-arm64 "${DEFINES[@]}"
APK=build/app/outputs/flutter-apk/app-release.apk
if [[ -n "$APKSIGNER" ]]; then
  CERT=$("$APKSIGNER" verify --print-certs "$APK" | grep 'certificate DN' || true)
  echo "==> Signed by: ${CERT#*: }"
  if grep -qi 'Android Debug' <<<"$CERT"; then
    echo "The APK is signed with the DEBUG key. Fix android/key.properties." >&2
    exit 1
  fi
fi
OUT="build/release/serafim-${NAME}.apk"
cp "$APK" "$OUT"
FILES+=("$OUT")

echo
echo "  version name : $NAME"
echo "  version code : $CODE"
echo "  tag          : $TAG"
for OUT in "${FILES[@]}"; do
  echo
  echo "  file         : $OUT"
  echo "  size (bytes) : $(stat -c %s "$OUT")"
  echo "  SHA-256      : $(sha256sum "$OUT" | awk '{print $1}')"
  echo "  download URL : https://github.com/${REPO}/releases/download/${TAG_URL}/$(basename "$OUT")"
done
echo

if command -v gh >/dev/null 2>&1; then
  NOTES_ARGS=(--notes "")
  [[ -n "$NOTES_FILE" ]] && NOTES_ARGS=(--notes-file "$NOTES_FILE")
  gh release create "$TAG" "${FILES[@]}" --title "Serafim $NAME" "${NOTES_ARGS[@]}"
  echo "==> Released. Now announce it from the official chat."
else
  echo "GitHub CLI not found. Create the release by hand:"
  echo "  1. https://github.com/${REPO}/releases/new"
  echo "  2. Tag: $TAG   Title: Serafim $NAME   Notes: what's new"
  echo "  3. Attach ${FILES[0]} and publish (not as a draft or pre-release)."
  echo "  4. Announce it from the official chat."
fi
