# Privacy Policy

<!-- DRAFT-NOTICE-START -->
> **DRAFT FOR LEGAL REVIEW.** This text was written to match how the app is designed (on-device video processing, no account, Google AdMob with consent, an open-source FFmpeg library). It is not legal advice and has not been reviewed by a lawyer. Have a qualified lawyer review it, and confirm the AdMob, consent and "delete original" details against the final build, before publishing. Delete this notice (the block between the DRAFT-NOTICE markers) before release. The website build script removes it automatically.
<!-- DRAFT-NOTICE-END -->

**App:** Video Compressor: Shrinkly ("Shrinkly")
**Company:** Ecom Swift LLC, 30 N Gould St #37906, Sheridan, WY 82801, United States
**Contact:** support@ecomswiftllc.com
**Last updated:** November 19, 2026

This policy explains what Shrinkly does with information. The short version: your videos are processed on your device and are never uploaded, and the only outside party that receives any data is the advertising service that pays for the app.

## 1. The short version

- Shrinkly has no account and no sign-in.
- Your videos are compressed, previewed and saved on your device. We do not upload them and we cannot see them.
- Shrinkly is free and shows ads from Google AdMob. AdMob collects some device and ad data to show and measure ads. You are asked for your consent where the law requires it.
- We do not run our own analytics, and there are no in-app purchases or subscriptions.
- Shrinkly itself builds no profile of you. Tracking can happen only through the ads: if you allow tracking when iOS asks, Google's advertising SDK may use your advertising identifier to show and measure ads, and Apple treats that as tracking. If you tap "Ask App Not to Track", it does not. See sections 4 and 5.

## 2. Videos and other information that stay on your device

You choose which videos to open. Shrinkly reads them through the iOS photo picker, so it does not need access to your whole photo library. You can also import a file from the Files app, or start from one of the sample clips built into the app. When you save a result to your photo library, Shrinkly asks for add-only permission, which lets it add new videos and does not let it read the rest of your library. Saving to the Files app or sharing through the iOS share sheet does not need photo library permission.

All processing happens on your device: reading the video (including formats such as MKV, AVI, WebM, WMV, FLV and TS, which are read with the open-source FFmpeg library built into the app), resizing, re-encoding with H.264 or HEVC, previewing the before and after, and writing the new file. Your videos, their audio, their metadata (such as the date and the location a camera may have stored) and the compressed results are not sent to Ecom Swift LLC, to Google, or to any server or AI service, and they are not used to train any model. If you choose to remove location and other metadata, the compressed copy is written without it. Shrinkly never changes or overwrites your original video.

While a video is being processed, Shrinkly keeps temporary working files in the app's own storage on your device. They are deleted when the job finishes, is cancelled, or the app next starts. The running total of space saved (the "You saved" counter) and your recent settings are stored on your device only.

If after saving a result you choose to delete the original video, iOS asks you to confirm and Shrinkly may ask for photo library access for that purpose. Deleting is never done without your confirmation.

When you save or share a result, Shrinkly gives the file to your photo library, the Files app or the iOS share sheet. Where it goes after that is your choice. We do not receive it.

Files that are protected by digital rights management (DRM), such as purchased or rented video from streaming and download stores, cannot be read by Shrinkly. Shrinkly does not try to bypass any protection.

## 3. Information we receive

**From the app:** none. We do not receive your videos, your identity or your usage of the app.

**From you, if you write to us:** if you email support@ecomswiftllc.com, we receive your email address and whatever you choose to write. We use it only to answer you and to keep a record of the request. We keep support emails for as long as needed to help you and to meet our legal duties, and then delete them. Please do not send videos or other sensitive material unless we ask for it.

**From the website:** the Shrinkly website pages (ecomswiftllc.github.io/shrinkly/) are static pages. They do not use cookies of their own, analytics scripts, advertising scripts or externally hosted fonts. Our web host may keep standard server logs (such as IP address and pages requested) for security and operation.

## 4. Advertising (Google AdMob)

Shrinkly is free and supported by ads shown through Google AdMob, a service of Google LLC. The app shows a banner ad on the Home screen and, before you save or share a finished video, offers one rewarded video ad that you choose to watch. There are no other ads, and no ad covers the compression controls.

To show and measure ads, the Google Mobile Ads SDK in the app may collect and use, according to Google:

- device identifiers, including the advertising identifier (IDFA) if you allow tracking, and other device and app identifiers
- your IP address and approximate location derived from it
- information about ads you see and interact with
- device, operating system and app information and diagnostic information such as crashes and performance

We do not receive this data and we do not combine it with anything we hold. Google's use of the data is described in the Google Privacy Policy (https://policies.google.com/privacy) and on the page "How Google uses information from sites or apps that use our services" (https://policies.google.com/technologies/partner-sites).

Some US state privacy laws treat advertising of this kind as "sharing" or "targeted advertising". Shrinkly does not sell your videos or photos. You can limit ad personalisation as described in the next section.

## 5. Your choices about ads and tracking

- **Consent form (EEA, UK and other regions where required).** Right after the welcome screens, a consent form from Google's User Messaging Platform may appear. You can accept, decline or manage your choices. You can reopen it later in Settings, in the Ad privacy choices row, where one is required.
- **Tracking prompt.** After the consent step, iOS may ask whether Shrinkly may track you across apps and websites owned by other companies (App Tracking Transparency). If you tap "Ask App Not to Track", the advertising identifier is not shared, and ads you see will be less personalised. The app works the same either way. Shrinkly itself does not combine your data across other companies' apps and websites. The only tracking that can happen is through Google's advertising SDK, which may use the advertising identifier to show and measure ads, and only if you allow it in the prompt.
- **iOS settings.** You can change the tracking choice at any time in Settings > Privacy & Security > Tracking, and reset your advertising identifier in the same area.
- **Ads cannot be switched off inside the app**, because ads are how Shrinkly is paid for. If you decline a consent form that applies in your region, ads may not load for you. In that case no banner appears, and when you save or share the export goes ahead without an ad.
- **Report an ad.** If you see an ad that is offensive, misleading or inappropriate, write to support@ecomswiftllc.com. Tell us roughly when and where in the app you saw it and what it showed. A screenshot helps. We review reports and block ad categories or advertisers through Google AdMob where we can.

## 6. Rewarded video before saving or sharing

A rewarded video is shown only if you choose to watch it, before a save, share or export. A batch of videos counts as one export and needs one ad. If you choose Not now, nothing is saved or shared and you can try again at any time. If no ad is available (for example when you are offline, when no ad can be shown, or when your consent choice does not allow ads), the export goes ahead without one. The app remembers that an ad was watched only on your device, for a short time. This record contains no personal information and is not sent anywhere.

## 7. Open-source software in the app

Shrinkly contains FFmpeg (licensed under the GNU Lesser General Public License, version 2.1 or later) and the libraries libvpx, libopus, libvorbis, libogg, LAME, libwebp and dav1d. They run on your device and do not send any data anywhere. Licences, version numbers and our offer of source code are on the Open-source licences page (https://ecomswiftllc.github.io/shrinkly/licenses/) and in Settings in the app.

## 8. Deleting your data

- Shrinkly has no account. Deleting the app from your device removes everything the app stores, including recent settings and the saved-space counter.
- Videos you saved to your photo library, and files you exported or shared, are outside the app. You manage and delete them where you saved or sent them.
- Your device's own backup (for example iCloud Backup or a computer backup) may contain a copy of the app's data according to your Apple settings. That copy is controlled by you and Apple, not by us.
- We hold no personal data about you from your use of the app, so there is nothing on our side to delete. For advertising data held by Google, use Google's controls (https://myadcenter.google.com) or contact Google.

## 9. Children

Shrinkly is a general video utility and is not directed to children under 13 (or under 16 where that is the local age of digital consent). We do not knowingly collect personal information from children. The app is not designed for the Kids category and does not use child-directed ad treatment. If you believe a child has sent us personal information, write to support@ecomswiftllc.com and we will delete it.

## 10. Your rights

Depending on where you live (for example the EEA, the UK, California and other US states), you may have rights to access, correct, delete, port or restrict the use of personal information, to object to certain processing, and to withdraw consent. Because we do not hold personal information from your use of the app, there is usually nothing for us to provide, but you can write to us at support@ecomswiftllc.com about any request and we will respond within the time the law requires. For data held by Google, exercise your rights with Google. You can also complain to your local data protection authority.

## 11. Security

Your videos and the app's temporary files are protected by the security of your device and by iOS app storage protections. We recommend a device passcode. No method of storage is completely secure, and you are responsible for the files you export and share.

## 12. International transfers

Google and its partners may process advertising data in the United States and other countries. Where required, they rely on legal transfer mechanisms described in Google's policies.

## 13. Changes to this policy

If we change how the app handles information, we will update this page and the "Last updated" date, and where a change is significant we will say so in the app's release notes.

## 14. Contact

Ecom Swift LLC
30 N Gould St #37906
Sheridan, WY 82801
United States
Email: support@ecomswiftllc.com
