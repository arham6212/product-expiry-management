#!/usr/bin/env bash
# Shorebird setup script
# Run this once locally to authenticate and initialize Shorebird for the project.

set -e

echo "1. Installing Shorebird CLI (if not installed)..."
if ! command -v shorebird &> /dev/null; then
    curl -sS https://get.shorebird.dev | bash
    # Adjust PATH for the current session if needed
    export PATH="$PATH:$HOME/.shorebird/bin"
else
    echo "Shorebird CLI is already installed."
fi

echo "2. Running Shorebird doctor to verify installation..."
shorebird doctor

echo "3. Logging in to Shorebird..."
shorebird login

echo "4. Initializing Shorebird in this project..."
# This will create a shorebird.yaml file in the root directory.
shorebird init

echo "Setup complete! A shorebird.yaml file has been generated."
echo "NOTE: shorebird.yaml contains your Shorebird app_id. It is safe to commit."
