#!/usr/bin/env bash
# Creates a Shorebird patch (OTA update) for an existing Android release.

set -e

echo "Creating Shorebird Android Patch..."
shorebird patch android "$@"

echo "Android Patch deployed! Devices will download the patch on next launch."
