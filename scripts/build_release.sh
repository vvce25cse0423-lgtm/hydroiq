#!/bin/bash
# HydroIQ release build — Usage: ./scripts/build_release.sh
set -e
if [ ! -f ".env" ]; then
  echo "ERROR: .env not found. Copy .env.example and fill in your keys."; exit 1
fi
source .env
echo "Building HydroIQ release AAB..."
flutter build appbundle --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=WEATHER_API_KEY="$WEATHER_API_KEY" \
  --dart-define=GEMINI_API_KEY="$GEMINI_API_KEY" \
  --obfuscate \
  --split-debug-info=build/debug-info
echo "Done: build/app/outputs/bundle/release/app-release.aab"
