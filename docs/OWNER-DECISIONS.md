# Owner decisions for Shrinkly (read before changing monetisation, design or store copy)

**2026-11-19, from the owner's brief: Shrinkly stays FREE. No in-app purchases, no subscription, no StoreKit, no watermark.**
Each export (save, share, export) is paid for with one opt-in AdMob rewarded ad; a batch is one ad. **If no ad is ready, or consent is pending, the export is simply free.** A banner appears on Home only. Do not add purchases, export packs or Premium without asking the owner.

Other standing owner orders that apply here:

- All apps must work on iPhone and iPad (universal build, iPad layouts, 13 inch screenshots).
- Design: clean, premium, luxury, professional SaaS. Ink `#0C1519` / surface `#14232A` / raised `#1D3038`, ivory `#F2EEE4`, mist `#8FA3AB`, glacier mint `#7FE3CF` (saved, success), champagne `#E6C98B` (premium action), serif display (Fraunces on the web and slides, New York in the app). The motif is compression: a long bar collapsing to a short mint bar. No placeholder images, no clip art, no login-required design services.
- Real photos and professional icons only (sample clips: Pexels, credits in `docs/store/media-credits.md`).
- Store name: search keywords first, brand last, one colon: "Video Compressor: Shrinkly" (26 characters). Home-screen name "Shrinkly".
- No false claims: no "AI" wording, no review or star claims, no "any video" or "all formats", no claim that DRM-protected video works, nothing the CI cannot prove.
- Never violate Google Play / AdMob / Apple policy. `NSPrivacyTracking` stays false in the manifest (ITMS-91064); the tracking answer lives in the App Store Connect privacy label.
- Pace App Store submissions: do not submit several new apps on the same day.

## Open items that only the owner can do

1. After the app exists in App Store Connect: link the App Store listing in AdMob (status "Requires review", limited ad serving until then). AdMob app id `ca-app-pub-8621573128492952~1694462176`, see `docs/store/admob.md`.
2. App Store Connect forms that need the owner's personal data (review contact phone, trader status) and the App Privacy answers in `docs/store/app-privacy.md`.
3. **Lawyer review of the drafts**: privacy policy, terms of use and the open-source licences page (`docs/legal/privacy-policy.md`, `terms-of-use.md`, `open-source-licenses.md`). The pages on https://ecomswiftllc.github.io/shrinkly/ are published from these drafts with the draft banner stripped, so they are live and unreviewed. Points that most need a lawyer: the LGPL 2.1 notice, written source offer and "relink on request" statement for FFmpeg and LAME (dynamic framework on iOS), the DRM clause in the terms, the "delete original" wording, the limitation of liability and the governing-law clause, and patent wording for H.264/HEVC/AAC/MP3.
4. Confirm the privacy and terms text against the final build: the Photos permission wording (add-only plus picker, and whatever the "delete original" prompt needs), that Files import and Share are as described, that there is no camera or microphone use, the ad flow (one rewarded ad per export, batch = one, free when no ad), the temporary-file clean-up claim, and the Settings > Open-source licences screen.
5. Encryption export compliance: FFmpeg contains crypto code (AES, TLS for network inputs). The app opens local files only. Decide the `ITSAppUsesNonExemptEncryption` answer with the main session or a lawyer.
6. Re-run the store shot tools when the CI captures of the final build exist, and publish the new `website/shrinkly/assets/shots` if wanted (`python website/make_site_assets.py && python website/build_site.py`, then copy to the user-site repo).
7. The sample clip "Night Intersection" shows a few tiny, distant pedestrians at night (no faces). Replace it if you want zero risk.
8. AdMob: set the maximum ad content rating to General or Parental Guidance and block sensitive categories before launch (not changed by the brand pass).
