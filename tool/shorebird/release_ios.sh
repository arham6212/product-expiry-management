#!/usr/bin/env bash
# Creates a base Shorebird release for iOS (to submit to the App Store).

set -e

echo "Creating Shorebird iOS Release..."
shorebird release ios "$@"

echo "iOS Release created. You can now distribute the IPA via TestFlight/App Store."
