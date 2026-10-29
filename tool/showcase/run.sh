#!/usr/bin/env bash
# Renders showcase screenshots of the real app screens with mock data.
#
#   tool/showcase/run.sh
#
# Downloads (once) the app's Google Fonts and some free stock photos (Lorem
# Picsum, i.e. Unsplash-licensed) into build/showcase/cache, then renders
# tool/showcase/showcase_test.dart. The pictures land in build/showcase/.
# Nothing here is part of the app or its normal test run.
set -euo pipefail
cd "$(dirname "$0")/../.."
CACHE=build/showcase/cache
mkdir -p "$CACHE/fonts" "$CACHE/photos"

# The exact files google_fonts asks for (it checks their hashes):
# Bangers 400, Inter 300-900, JetBrains Mono 400-800.
FONTS=(
  5a00055f83a5ff74e6d71928101b6f38266dd28cc7972edd315b3758cad8b746
  2e9b3d490cbe065fcdc783c1c6220b6f2ce5f1b1c5b81b0c8a9f8b4f27519257
  ecdb53099b1a68cd24c6900ea5beeafec81bd3c8cb9d0f3c51b9986583ba3982
  492dec3bc33255f9d81bd5fb18704ad72f96f9b9318e4171bc9f9be9dd4bf44b
  d7ba633bab7f40576e539a7e934a1301d7618dceea59c743de477c2c493462fc
  b7e339223d56e8c4210c86f1ba87b3d43d6c47e03956ea56f0a7a938ae61b2a3
  06fb8b97ad04af6b7fa9f2fb17d3763d28f6694f777f33dcf147e84c55a4e81a
  7485a755eabadd6c1b38664e848793fd919674ab8d09c25e9347e93bea9a7177
  fc34426314d00825ccc768a0c4b1178fe704f04bd947882ef10c2b71b7e355e7
  ba10286722bd7dc2274b817575046e39ee816d6ba1e2ace48e22bcd068576941
  f833596d98e0e021dd43d993254658d0f32318f82f08afee0fc2e41c16ce9571
  b43a7dfebfb8816fb3859f6a7932824f594e115538ccd3f1ebc0ffc231b0acab
  98ea78a2337e1ef2274f247c857a63e40e975c6907a7baff9209033fa42142ac
)
for h in "${FONTS[@]}"; do
  [[ -s "$CACHE/fonts/$h.ttf" ]] ||
    curl -sfL -o "$CACHE/fonts/$h.ttf" "https://fonts.gstatic.com/s/a/$h.ttf"
done

# Mock photos by fixed Picsum id, so every run looks the same.
# Avatars (square) then post pictures (4:3).
for id in 64 65 91 338 1005 1027 1011 177; do
  [[ -s "$CACHE/photos/a$id.jpg" ]] ||
    curl -sfL -o "$CACHE/photos/a$id.jpg" "https://picsum.photos/id/$id/300/300"
done
for id in 1015 1036 1039 1080 292 429 1060 1062 431 1043; do
  [[ -s "$CACHE/photos/p$id.jpg" ]] ||
    curl -sfL -o "$CACHE/photos/p$id.jpg" "https://picsum.photos/id/$id/1200/900"
done

FLUTTER_ROOT_DIR="$(dirname "$(dirname "$(readlink -f "$(command -v flutter)")")")"
SHOWCASE_CACHE="$PWD/$CACHE" \
SHOWCASE_OUT="$PWD/build/showcase" \
SHOWCASE_ICONS="$FLUTTER_ROOT_DIR/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf" \
  flutter test tool/showcase/showcase_test.dart "$@"
echo "==> Screenshots in build/showcase/"
