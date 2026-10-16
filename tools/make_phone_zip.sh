#!/bin/bash
# Build the phone copy of the game from this (the one and only) project.
# The phone zip is a trimmed COPY: Android voxel libraries only, no tools,
# tests or reference. Never unzip it over the PC folder or copy files back
# from the phone - all changes are made here and go to both from here.
# Usage: tools/make_phone_zip.sh OUT.zip
set -e
out=${1:-BushPilot2_phone.zip}
cd "$(dirname "$0")/../.."
rm -f "$out"
zip -q -r -9 "$out" bushpilot2 -x "bushpilot2/.godot/*" "bushpilot2/tools/*" "bushpilot2/export/*" "bushpilot2/reference/*" "bushpilot2/tests/*" \
  "bushpilot2/addons/zylann.voxel/bin/*windows*" "bushpilot2/addons/zylann.voxel/bin/*linux*" "bushpilot2/addons/zylann.voxel/bin/*ios*" \
  "bushpilot2/addons/zylann.voxel/bin/*macos*" "bushpilot2/addons/zylann.voxel/bin/*x86_64*"
echo "phone build: $out"
