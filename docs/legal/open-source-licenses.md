# Open-source licences

<!-- DRAFT-NOTICE-START -->
> **DRAFT FOR LEGAL REVIEW.** The notices below match the FFmpeg build described in https://github.com/EcomswiftLLC/ffmpeg-ios-lgpl (NOTICE.md and scripts/versions.env). Re-check every version number and licence against the exact framework that ships in each app release, and have a lawyer review the LGPL wording and the relinking statement. Delete this notice before release. The website build script removes it automatically.
<!-- DRAFT-NOTICE-END -->

**App:** Video Compressor: Shrinkly ("Shrinkly")
**Company:** Ecom Swift LLC, 30 N Gould St #37906, Sheridan, WY 82801, United States
**Contact:** support@ecomswiftllc.com
**Last updated:** November 19, 2026

Shrinkly is built with open-source software. This page lists it, gives the licences, and explains how to get the source code. The same information is in Settings, under Open-source licences, in the app.

## FFmpeg (GNU Lesser General Public License, version 2.1 or later)

Shrinkly uses FFmpeg libraries (libavformat, libavcodec, libavfilter, libswscale, libswresample and libavutil), version 7.1.1, to read video formats that iOS cannot read by itself, such as MKV, AVI, WebM, WMV, FLV and TS. FFmpeg is configured without --enable-gpl, --enable-version3 and --enable-nonfree, so it is licensed under the GNU Lesser General Public License (LGPL), version 2.1 or later. The licence text is at https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html and the FFmpeg project is at https://ffmpeg.org/. FFmpeg is a trademark of Fabrice Bellard, originator of the FFmpeg project. Shrinkly is not affiliated with or endorsed by the FFmpeg project.

FFmpeg is included as a dynamic framework (FFmpegLGPL.xcframework), not compiled into the app's own code. It is built, unmodified, by the open scripts at https://github.com/EcomswiftLLC/ffmpeg-ios-lgpl (build script scripts/build.sh and exact versions in scripts/versions.env). No upstream source is modified.

## Other libraries in the same framework

- libvpx (VP8 and VP9), version 1.14.1, BSD 3-Clause
- libopus, version 1.5.2, BSD 3-Clause
- libvorbis, version 1.3.7, BSD 3-Clause
- libogg, version 1.3.5, BSD 3-Clause
- LAME (libmp3lame), version 3.100, LGPL 2.1 or later
- libwebp, version 1.4.0, BSD 3-Clause
- dav1d (AV1 decoder), version 1.5.0, BSD 2-Clause

Hardware H.264 and HEVC encoding and AAC use Apple's VideoToolbox and AudioToolbox frameworks, which are part of iOS. The app does not include x264, x265 or fdk-aac.

## Your rights under the LGPL, and a written offer of source code

You may get the complete corresponding source code of the LGPL libraries in the app, you may replace them with your own modified version, and you may reverse engineer the app as far as needed to debug such modifications, as the LGPL provides.

- Source and build: the exact upstream versions are listed above and in scripts/versions.env, and the download addresses and build steps are in scripts/build.sh, at https://github.com/EcomswiftLLC/ffmpeg-ios-lgpl. FFmpeg source is also at https://ffmpeg.org/releases/.
- Written offer: for three years after you received a copy of Shrinkly, write to support@ecomswiftllc.com and we will send you the complete corresponding source code of these libraries on request, at no more than the cost of providing it.
- Replacing the library: the libraries are in a dynamic framework. Build your own version with the scripts above. If you want to use a modified version with the app, write to us and we will tell you how to relink or re-sign it, as the LGPL requires.

Some video and audio formats (such as H.264, HEVC, AAC and MP3) may be covered by patents in some countries. You are responsible for your use of them.

## Google Mobile Ads SDK and User Messaging Platform

The app uses the Google Mobile Ads SDK and Google's User Messaging Platform SDK to show ads and to ask for consent. They are provided by Google LLC under Google's own terms (https://developers.google.com/admob/terms) and are not open source. What they collect is described in the Privacy Policy.

## Fonts on this website

The pages of this website use the typefaces Fraunces and Inter, which are licensed under the SIL Open Font License, version 1.1 (https://openfontlicense.org/). They are served from this website, not from another host. The app itself uses the system fonts of iOS.

## Sample videos

The sample clips in the app are from Pexels and used under the Pexels License (https://www.pexels.com/license/). Creators: Nui MALAMA, Evgenij Mikhailov, Ndumiso Mvelase and Dmitry Marchenkov.

## Contact

Ecom Swift LLC
30 N Gould St #37906
Sheridan, WY 82801
United States
Email: support@ecomswiftllc.com
