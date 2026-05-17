---
description: Updating RevenueCat Tiers & Entitlements
---

# 🚀 Merian RevenueCat Paywall Runbook

Merian delegates subscription entitlements via RevenueCat natively. Bumping tiers, adding promotional codes, or debugging receipt validation issues requires updating the localized `.storekit` file, `GamificationManager`, and RevenueCat payloads securely. 

## Step 1: Initialize the New App Store Connect Identifier
1. If you are launching `merian_pro_yearly_promo_50`, it must first be registered in App Store Connect.
2. In the Xcode workspace (`apps/ios/Merian/Configuration/StoreKit/`), open the `.storekit` mock file and replicate the identifier verbatim.

## Step 2: Bind the RevenueCat Entitlement
Merian utilizes a standard Entitlement ID (`pro`) across all tiers.
- In `AppDIContainer.revenueCatManager` or `RevenueCatManager.swift`, locate where the active entitlement check occurs:

```swift
let customerInfo = try await Purchases.shared.customerInfo()
let hasPro = customerInfo.entitlements["pro"]?.isActive == true
```
> [!NOTE]
> Do NOT touch the `pro` entitlement string unless you are introducing a completely new permission level (like `merian_enterprise`). Changing the core string globally strips pro capabilities from legacy users.

## Step 3: Integrate with the Core UI & Paywall
1. Ensure the `ModelTierBadge` and `PaywallView` logic correctly evaluates the new offering package payload.
2. Because Merian is offline-first, verify that the active `TelemetryDeck` initialization gracefully reports standard user engagement without sending their precise billing details!

## Step 4: Simulator Testing using StoreKit Validation
Instead of running a physical iPad/iPhone test with production Sandbox credentials every time:

1. Under Xcode 'Edit Scheme' > Options > StoreKit Configuration, ensure it is locked to your `Merian.storekit` mock file.
2. Run the application locally in the simulator.
3. Tap the "Subscribe" button on the UI—a native UI alert via StoreKit 2 will trigger immediately. 

## Step 5: Dashboard Configuration & Deployment
After successful local validation:
1. Log in to your RevenueCat Dashboard.
2. Under "Products", paste the EXACT App Store Connect ID.
3. Attach the product to an explicit "Offering" so it gets bundled to the SwiftUI Paywall view payload.
4. If it serves as the new default pricing logic, swap the fallback IDs in your `MerianApp.swift` or `RevenueCatManager` configurations as well.
