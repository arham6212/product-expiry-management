#!/usr/bin/env bash
# Creates a Shorebird patch (OTA update) for an existing iOS release.

set -e

echo "Creating Shorebird iOS Patch..."
shorebird patch ios "$@"

echo "iOS Patch deployed! Devices will download the patch on next launch."
