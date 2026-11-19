# Shrinkly: AdMob ids

Created 2026-11-19 in the Ecom Swift AdMob account (publisher `pub-8621573128492952`), through the owner's logged-in Chrome. No payment or tax data was entered.

| Item | Name in AdMob | Id |
|---|---|---|
| iOS app (not yet in the App Store, answered "No" to "listed on a supported app store") | Video Compressor: Shrinkly | `ca-app-pub-8621573128492952~1694462176` |
| Banner ad unit | Shrinkly Home Banner | `ca-app-pub-8621573128492952/9876204528` |
| Rewarded ad unit (reward: 1 Reward) | Shrinkly Export Rewarded | `ca-app-pub-8621573128492952/1950000089` |

- AdMob console app page: https://admob.google.com/v2/apps/1694462176/overview
- `Config/Release.xcconfig` holds these three ids (`ADMOB_APP_ID`, `ADMOB_BANNER_UNIT_ID`, `ADMOB_REWARDED_UNIT_ID`). `Config/Debug.xcconfig` keeps Google's public test ids. `.github/workflows/release.yml` refuses test ids in a release.
- Status in AdMob: "Requires review", limited ad serving, until the App Store listing is linked. New units may take up to an hour to serve ads. After the app is live: AdMob > Apps > Video Compressor: Shrinkly > Add store listing.
- `app-ads.txt` already lists this publisher id at https://ecomswiftllc.github.io/app-ads.txt (shared by every app of the account). Set the developer website of the App Store listing so Apple and AdMob can match it.
- Recommended in AdMob: maximum ad content rating General or Parental Guidance and block sensitive categories, to match the 4+ age rating (not changed in this pass).
- Policy reminders (HARD): the banner appears on Home only, never over the compress setup controls or the result; the rewarded ad is opt-in with a clear prompt before each save/share/export (a batch is one ad), and the export is free when no ad is ready.
