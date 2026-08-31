#!/bin/sh
set -e
git clone https://github.com/flutter/flutter.git -b 3.38.6 --depth 1 _flutter_sdk
export PATH="$PATH:$(pwd)/_flutter_sdk/bin"
flutter pub get

# Strip any stray whitespace/newlines Vercel's env-var storage might add —
# an embedded newline here gets parsed by flutter as a second positional
# "target file" arg and fails the build.
SUPABASE_URL=$(printf '%s' "$SUPABASE_URL" | tr -d '[:space:]')
SUPABASE_ANON_KEY=$(printf '%s' "$SUPABASE_ANON_KEY" | tr -d '[:space:]')

flutter build web --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
