#!/usr/bin/env bash
# Creates a base Shorebird release for Android (to submit to the Play Store).

set -e

echo "Creating Shorebird Android Release..."
# Note: Add --flavor or other flags if needed in the future.
shorebird release android "$@"

echo "Android Release created. You can now distribute the AAB or APK to users."
