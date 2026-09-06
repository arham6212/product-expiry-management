# Shorebird Integration

This directory contains the infrastructure scripts for integrating Shorebird (Code Push) into the Flutter application. 

As per the architectural guidelines, Shorebird is treated strictly as an infrastructure and release feature. It is completely isolated from the application's business logic, state management, and UI. Existing Flutter build tools (`flutter build ...`) remain unmodified and fully functional for standard builds.

## Setup Instructions

To initialize Shorebird on your local machine for the first time, run:

```bash
./tool/shorebird/setup.sh
```

This script will:
1. Install the Shorebird CLI via the official installation method (`curl -sS https://get.shorebird.dev | bash`).
2. Run `shorebird doctor` to verify the installation and dependencies.
3. Prompt you to log in to your Shorebird account (`shorebird login`).
4. Initialize Shorebird in the project root (`shorebird init`), creating a `shorebird.yaml` file containing the `app_id`.

## Releases and Patches

Shorebird separates updates into **Releases** (base builds submitted to App Stores) and **Patches** (OTA code updates deployed to users).

### Android
*   **Create Release (App Store):** `./tool/shorebird/release_android.sh`
*   **Deploy Patch (OTA):** `./tool/shorebird/patch_android.sh`

### iOS
*   **Create Release (App Store):** `./tool/shorebird/release_ios.sh`
*   **Deploy Patch (OTA):** `./tool/shorebird/patch_ios.sh`

## Notes
*   These scripts wrap standard Shorebird commands. You can pass additional arguments (e.g., `--flavor`) directly to the scripts.
*   The `shorebird.yaml` file generated during setup is safe to commit to version control, as it only contains a public `app_id` and no secrets.
