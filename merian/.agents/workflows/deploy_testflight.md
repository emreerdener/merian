---
description: TestFlight Beta Deployment via Fastlane
---

# 🚀 Merian Fastlane Automated Deployment

This project uses `fastlane` to bypass manual Xcode archives. Since we use `xcodegen`, Fastlane ensures the `.xcodeproj` is generated before it begins its sequence, incrementing the build number dynamically from App Store Connect, signing the executable, and initiating the upload.

## Step 1: Prepare Authentication
You must be authenticated with Apple's developer servers locally to run this.
1. If you haven't yet, log in to your Apple ID locally:
```bash
fastlane spaceauth
```
2. Or have your App Store Connect API keys exported into your terminal (`FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD`).

## Step 2: Triggering the Deployment

// turbo-all
```bash
cd fastlane
fastlane beta
```

## Step 3: Wait for Processing
After the console indicates the `.ipa` has been successfully uploaded, App Store Connect will put it into a `Processing` state. Once complete, it will be automatically distributed to your Internal Testers list.
