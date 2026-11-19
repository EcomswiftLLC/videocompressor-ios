# Shrinkly: App Privacy answers (App Store Connect, "App Privacy")

These answers describe the planned build: no analytics of our own, no account, videos processed on the device and never uploaded, ads from Google AdMob (Google Mobile Ads SDK + UMP) with the App Tracking Transparency prompt. They match `Sources/Resources/PrivacyInfo.xcprivacy` (`NSPrivacyTracking` stays false in the manifest, as required for ITMS-91064; Apple's label, not the manifest flag, carries the tracking answer) and the privacy policy at https://ecomswiftllc.github.io/shrinkly/privacy/. Same answers as Lumotion, Aperta and Folia.

## Data collection

"Do you or your third-party partners collect data from this app?" Yes.

| Data type | Collected | Linked to the user | Used to track | Purposes |
|---|---|---|---|---|
| Identifiers: Device ID | Yes | Yes | **Yes** | Third-Party Advertising (and Analytics, as Google reports it) |
| Usage Data: Advertising Data | Yes | Yes | **Yes** | Third-Party Advertising |
| Usage Data: Product Interaction | Yes | Yes | No | Third-Party Advertising |
| Diagnostics: Performance Data | Yes | Yes | No | Third-Party Advertising, Analytics (ad SDK diagnostics) |
| Location: Coarse Location | Yes | **No** | No | Third-Party Advertising |
| Diagnostics: Crash Data | Yes | **No** | No | Analytics |

Everything else: **No**. In particular: Photos or Videos, Audio Data, Contacts, User Content, Name, Email, Purchases, Search History, Browsing History, Precise Location, Health and Fitness, Financial Info, Sensitive Info. The user's videos never leave the device: reading, encoding (including the FFmpeg engine) and saving are all local, and the FFmpeg library makes no network calls in this app.

## Tracking

"Does this app use data for tracking?" **Yes**: Device ID and Advertising Data (the IDFA, only if the user allows tracking in the ATT prompt) are used by Google's advertising SDK for third-party advertising. The app shows the ATT prompt after the UMP consent step. `NSUserTrackingUsageDescription` is in Info.plist.

## Notes for the person filling the form

- Answer per Apple's definitions: data a third-party SDK (Google Mobile Ads) collects counts as collected by the app.
- Privacy Policy URL: https://ecomswiftllc.github.io/shrinkly/privacy/
- If a later version adds analytics, a crash reporter, sign-in, an online conversion or any upload, update this file, `PrivacyInfo.xcprivacy`, the policy page and the ASC answers together before submitting.
- The "delete original after saving" feature uses the photo library's delete request, which can need library access. It reads nothing for us and uploads nothing, so no label changes, but the Photos usage description strings in Info.plist must cover it (main session).
