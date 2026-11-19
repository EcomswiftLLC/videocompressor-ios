"""Builds the static Shrinkly site into website/shrinkly/.

  python website/build_site.py
  (optional) SHRINKLY_SUPPORT_EMAIL=<public support address>   overrides the address read from docs/legal
  (optional) SHRINKLY_SITE_OUT=<folder>                         write the pages somewhere else (review builds)

The support address is read from the "Contact:" line of docs/legal/privacy-policy.md unless the environment
variable is set, so it is never hard coded here. It is shown on the pages as selectable text (no mailto link,
which is unreliable in many mail setups and invites scraping).

Writes index.html, support/, privacy/, terms/, licenses/ (each an index.html), sitemap.xml, robots.txt.
The privacy, terms and licences pages are generated from docs/legal/*.md, so edit the Markdown and re-run this script.
The draft notice block in those files (between the DRAFT-NOTICE markers) is stripped from the web pages.
Assets (CSS, fonts, images) live in website/shrinkly/assets (images come from website/make_site_assets.py).
If website/shrinkly/assets/shots/*.jpg exist (real app captures) the home page shows them.
Needs tools/make_icon.py and website/make_site_assets.py (Pillow, numpy) only for the asset step, not for this script.
Published by copying website/shrinkly/ to the /shrinkly/ folder of EcomswiftLLC/ecomswiftllc.github.io.
"""
import html
import json
import os
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC_SITE = ROOT / "website" / "shrinkly"
OUT = Path(os.environ.get("SHRINKLY_SITE_OUT") or SRC_SITE)
LEGAL = ROOT / "docs" / "legal"

BASE = "https://ecomswiftllc.github.io/shrinkly/"
UPDATED = "2026-11-19"
SITE_NAME = "Video Compressor: Shrinkly"


def read_support_email():
    env = os.environ.get("SHRINKLY_SUPPORT_EMAIL", "").strip()
    if env:
        return env
    text = (LEGAL / "privacy-policy.md").read_text(encoding="utf-8")
    m = re.search(r"\*\*Contact:\*\*\s*(\S+@\S+)", text)
    if not m:
        sys.exit("No support address: set SHRINKLY_SUPPORT_EMAIL or keep the Contact line in docs/legal/privacy-policy.md.")
    return m.group(1).strip()


SUPPORT_EMAIL = read_support_email()


# ----------------------------------------------------------------------------- shell
def head(title, description, path, extra_head="", root=""):
    canonical = BASE + path
    t = html.escape(title)
    d = html.escape(description)
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>{t}</title>
<meta name="description" content="{d}">
<link rel="canonical" href="{canonical}">
<meta name="theme-color" content="#0C1519">
<meta name="color-scheme" content="dark">
<link rel="icon" href="{root}assets/favicon.svg" type="image/svg+xml">
<link rel="icon" href="{root}assets/favicon-32.png" type="image/png" sizes="32x32">
<link rel="apple-touch-icon" href="{root}assets/apple-touch-icon.png">
<link rel="preload" href="{root}assets/fonts/fraunces-latin.woff2" as="font" type="font/woff2" crossorigin>
<meta property="og:type" content="website">
<meta property="og:site_name" content="{html.escape(SITE_NAME)}">
<meta property="og:title" content="{t}">
<meta property="og:description" content="{d}">
<meta property="og:url" content="{canonical}">
<meta property="og:image" content="{BASE}assets/og-image.png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="The Shrinkly app icon, a play triangle squeezed between two brackets, next to the words Make big videos small">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="{t}">
<meta name="twitter:description" content="{d}">
<meta name="twitter:image" content="{BASE}assets/og-image.png">
<link rel="stylesheet" href="{root}assets/site.css">
{extra_head}</head>
<body>
<a class="skip" href="#main">Skip to content</a>
"""


def header(root, current=""):
    def a(href, text, key):
        cur = ' aria-current="page"' if key == current else ""
        return f'<a href="{href}"{cur}>{text}</a>'
    home = root or "./"
    return f"""<header class="site-header">
  <div class="wrap">
    <a class="brand" href="{home}"><img src="{root}assets/shrinkly-mark.svg" alt="" width="34" height="34">Shrinkly</a>
    <nav class="nav" aria-label="Main">
      {a(home + '#how', 'How it works', 'h')}
      {a(home + '#features', 'Features', 'f')}
      {a(home + '#formats', 'Formats', 'o')}
      {a(home + '#private', 'Privacy', 'p')}
      {a(home + '#free', 'Free with ads', 'a')}
      {a(home + '#faq', 'FAQ', 'q')}
      {a(root + 'support/', 'Support', 'support')}
    </nav>
  </div>
</header>
"""


def footer(root):
    home = root or "./"
    return f"""<footer class="site-footer">
  <div class="wrap">
    <div>
      <h2>Video Compressor: Shrinkly</h2>
      <p>A free video compressor for iPhone and iPad. Your videos are processed on your device. Not on the App Store yet.</p>
    </div>
    <nav aria-label="Footer">
      <h2>Pages</h2>
      <ul>
        <li><a href="{home}">Home</a></li>
        <li><a href="{root}support/">Support</a></li>
        <li><a href="{root}privacy/">Privacy policy</a></li>
        <li><a href="{root}terms/">Terms of use</a></li>
        <li><a href="{root}licenses/">Open-source licences</a></li>
      </ul>
    </nav>
    <div>
      <h2>Ecom Swift LLC</h2>
      <p>30 N Gould St #37906<br>Sheridan, WY 82801<br>United States</p>
      <p class="email">{html.escape(SUPPORT_EMAIL)}</p>
    </div>
    <p class="legalline">&copy; 2026 Ecom Swift LLC. Apple, iPhone, iPad and the App Store are trademarks of Apple Inc. WhatsApp, Telegram, Discord, Instagram, TikTok, X and YouTube are trademarks of their owners and are named only to say which services the presets are made for; Shrinkly is not affiliated with them or with Apple or Google. Sample clips are from Pexels. Shrinkly uses FFmpeg under the LGPL, see Open-source licences.</p>
  </div>
</footer>
</body>
</html>
"""


# ----------------------------------------------------------------------------- home
EMAIL_TEXT = f'<span class="email">{html.escape(SUPPORT_EMAIL)}</span>'

FAQ = [
    ("Is Shrinkly really free?",
     "<p>Yes. There is no subscription, no in-app purchase, no paid version and no watermark. Ads from Google AdMob pay for the app: a banner on the Home screen, and one rewarded video that you choose to watch before you save or share.</p>"),
    ("Are my videos uploaded anywhere?",
     "<p>No. Reading, compressing, previewing and saving all happen on your device. We never receive your videos, and nothing is sent to an online converter or an AI service.</p>"),
    ("Do I need an account?",
     "<p>No. There is no sign-in and no sign-up.</p>"),
    ("How do I get a video under a size limit?",
     "<p>Choose the video, then pick a preset such as WhatsApp or Email, or type the size you need in MB. Shrinkly shows an estimate before it starts and aims for that size. Presets are starting points, and services change their limits, so check the target in the preset against the current limit of the app you are sending to.</p>"),
    ("Why can't a video be made smaller?",
     "<p>Every video has a floor. A long clip squeezed into a few megabytes needs a very low bitrate, and below a point the picture turns to blocks. When your target is lower than that, Shrinkly says so and suggests what to change: a lower resolution, a lower frame rate, HEVC, a shorter clip with the trim tool, or a bigger target.</p>"),
    ("Which formats can it open?",
     "<p>Videos that iOS plays, such as MP4, MOV and M4V, and many that it does not, such as MKV, AVI, WebM, WMV, FLV, MPEG and TS, which are read with the open-source FFmpeg library built into the app. The result is saved as an MP4 or MOV in H.264 or HEVC. See the table on this page for the list.</p>"),
    ("Does it work with protected videos?",
     "<p>No. Videos protected by digital rights management (DRM), such as purchases and rentals from streaming or download stores, cannot be read by any app other than the one that sold them. Shrinkly shows a clear message when it meets one and does not try to bypass protection.</p>"),
    ("Why am I asked to watch an ad?",
     "<p>Before a save, share or export, the app offers one short video that you choose to watch. A batch of videos needs one ad. If you choose Not now, nothing is saved and you can try again any time. If no ad is available, for example when you are offline, the export goes ahead anyway. Compressing and previewing never need an ad.</p>"),
    ("Does it change my original video?",
     "<p>Never. Shrinkly always writes a new file. After you save, it can offer to delete the original, and nothing is deleted unless you confirm.</p>"),
    ("Does it need photo library access?",
     "<p>Not to choose videos: you pick them with the iOS photo picker and Shrinkly sees only the ones you choose. To save a result, the app asks for add-only permission, which lets it add videos and does not let it read your library. You can also import from the Files app and save back to Files.</p>"),
    ("What happens if I do not allow tracking?",
     "<p>The app works the same. The ads you see will be less personalised. You can change the choice any time in iOS Settings under Privacy and Security, then Tracking. Shrinkly itself runs no analytics. If you allow tracking, only Google's ad software may use your advertising identifier for ads.</p>"),
    ("Which devices does it run on?",
     "<p>iPhone and iPad with iOS 17 or iPadOS 17 or later, in portrait and landscape.</p>"),
    ("When can I download it?",
     "<p>Shrinkly is not on the App Store yet, so there is no download link. This page will link to the App Store listing once the app is available.</p>"),
    ("Who makes Shrinkly?",
     "<p>Ecom Swift LLC, a company registered in Wyoming, United States. You can reach us on the <a href=\"support/\">support page</a>.</p>"),
]


def jsonld_app():
    data = {
        "@context": "https://schema.org",
        "@type": "SoftwareApplication",
        "name": SITE_NAME,
        "alternateName": "Shrinkly",
        "url": BASE,
        "applicationCategory": "MultimediaApplication",
        "operatingSystem": "iOS 17.0 or later",
        "description": "A free video compressor for iPhone and iPad. Shrink a video to a size in MB or a quality level, use presets for popular apps, compress a batch, compare before and after, and save as H.264 or HEVC. Everything is processed on the device. Supported by ads.",
        "image": BASE + "assets/icon-512.png",
        "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"},
        "publisher": {"@type": "Organization", "name": "Ecom Swift LLC", "url": "https://www.ecomswiftllc.com/",
                      "address": {"@type": "PostalAddress", "streetAddress": "30 N Gould St #37906",
                                  "addressLocality": "Sheridan", "addressRegion": "WY", "postalCode": "82801",
                                  "addressCountry": "US"}},
        "featureList": [
            "Compress to a target size in MB, or by quality",
            "Presets for WhatsApp, Telegram, Discord, email, Instagram and Reels, TikTok, X, YouTube Shorts and Messages",
            "Batch compression with a total space saved counter",
            "Before and after size and quality comparison",
            "H.264 or HEVC output",
            "Opens MKV, AVI, WebM, WMV, FLV, TS and more",
            "Processed on the device, no account",
        ],
    }
    return '<script type="application/ld+json">\n' + json.dumps(data, indent=2) + "\n</script>\n"


def jsonld_faq():
    plain = lambda s: html.unescape(re.sub(r"<[^>]+>", "", s))
    data = {"@context": "https://schema.org", "@type": "FAQPage",
            "mainEntity": [{"@type": "Question", "name": q,
                            "acceptedAnswer": {"@type": "Answer", "text": plain(a)}} for q, a in FAQ]}
    return '<script type="application/ld+json">\n' + json.dumps(data, indent=2) + "\n</script>\n"


REEL = [
    ("rocky-surf", "Rocky Surf", "High motion, bright water. A tough one to shrink.", "Waves crashing on dark rocks"),
    ("night-intersection", "Night Intersection", "Dark and detailed. Noise makes files big.", "A city intersection at night with car lights"),
    ("cloud-field", "Cloud Field", "Calm and smooth. Shrinks a lot.", "White clouds over a green field"),
    ("reed-sunset", "Reeds at Sunset", "A vertical clip, like one shot on a phone.", "Reed grass in silhouette against an evening sky"),
]


def reel_html():
    items = "\n".join(
        f'        <li><figure><img src="assets/samples/{n}.jpg" alt="{html.escape(alt)}" width="900" loading="lazy" decoding="async">'
        f'<figcaption><strong>{html.escape(t)}</strong><span>{html.escape(c)}</span></figcaption></figure></li>'
        for n, t, c, alt in REEL)
    return f"""  <section class="reel-section" aria-labelledby="h-reel">
    <div class="wrap">
      <div class="reel-head">
        <h2 id="h-reel">Try it before you pick a video of your own</h2>
        <p>Shrinkly comes with four sample clips, so you can see how a size target works on footage that is easy and hard to compress. These are frames from them.</p>
      </div>
      <ul class="reel">
{items}
      </ul>
      <p class="small reel-note">Sample clips are by Pexels creators and are used under the Pexels License.</p>
    </div>
  </section>
"""


SHOT_ALTS = [
    "Shrinkly on iPhone: the Home screen",
    "Shrinkly on iPhone: setting a size target in MB",
    "Shrinkly on iPhone: the presets list",
    "Shrinkly on iPhone: advanced options",
    "Shrinkly on iPhone: compressing a video",
    "Shrinkly on iPhone: the result with original and new size",
]


def shots_html():
    d = SRC_SITE / "assets" / "shots"
    shots = sorted(d.glob("*.jpg")) if d.exists() else []
    if not shots:
        return ""
    items = "\n".join(f'        <li><img src="assets/shots/{p.name}" alt="{html.escape(SHOT_ALTS[i - 1] if i <= len(SHOT_ALTS) else "Shrinkly on iPhone")}" width="660" loading="lazy" decoding="async"></li>'
                      for i, p in enumerate(shots, 1))
    return f"""  <section class="reel-section" aria-labelledby="h-shots">
    <div class="wrap">
      <div class="reel-head"><h2 id="h-shots">See it in the app</h2></div>
      <ul class="shots">
{items}
      </ul>
    </div>
  </section>
"""


def build_index():
    title = "Video Compressor: Shrinkly | Make big videos small"
    desc = "Free video compressor for iPhone and iPad. Shrink a video to a size in MB for WhatsApp, email or Messages, compress a batch, compare before and after, and keep every video on your device. No account."
    faq_html = "\n".join(
        f'        <details><summary>{html.escape(q)}</summary><div class="answer">{a}</div></details>' for q, a in FAQ)

    body = head(title, desc, "", jsonld_app() + jsonld_faq(), root="") + header("", "") + f"""
<main id="main">
  <section class="hero" aria-labelledby="h1">
    <div class="wrap">
      <div>
        <h1 id="h1">Make big videos small.</h1>
        <p class="lede">Shrinkly shrinks a video to the size you choose, so it fits WhatsApp, an email or a text. It is free, there is no account, and every video stays on your device.</p>
        <p class="status">Not on the App Store yet</p>
        <p class="small hero-note">There is no download link yet. Questions are welcome on the <a href="support/">support page</a>.</p>
      </div>
      <figure class="sizes" aria-labelledby="sizes-cap">
        <div class="row orig"><div class="cap"><span>Original video</span><b>48.0 MB</b></div><div class="track" aria-hidden="true"><div class="fill"></div></div></div>
        <div class="row after"><div class="cap"><span>After Shrinkly</span><b>6.2 MB</b></div><div class="track" aria-hidden="true"><div class="fill"></div></div></div>
        <div class="saved"><strong>&minus;87%</strong><span>smaller, so it is easier<br>to send and to store</span></div>
        <figcaption class="small" id="sizes-cap">An example. The size you get depends on your video and the target you pick.</figcaption>
      </figure>
    </div>
  </section>

{reel_html()}
{shots_html()}
  <section class="section" id="how" aria-labelledby="h-how">
    <div class="wrap">
      <h2 id="h-how">Pick, set a size, save.</h2>
      <div class="section-body">
        <ol class="steps">
          <li><div><h3>Choose a video</h3><p>Pick one or many from your photo library or the Files app, or start with a built-in sample clip.</p></div></li>
          <li><div><h3>Set the size</h3><p>Tap a preset such as WhatsApp or Email, or type the size you need in MB. Shrinkly shows an estimate before it starts.</p></div></li>
          <li><div><h3>Check and save</h3><p>Compare before and after, then save to Photos or Files, or share. Your original is never touched.</p></div></li>
        </ol>
      </div>
    </div>
  </section>

  <section class="section band" id="features" aria-labelledby="h-features">
    <div class="wrap">
      <h2 id="h-features">Everything you need to shrink a video</h2>
      <div class="section-body">
        <dl class="defs">
          <div><dt>By size, by quality, or by preset</dt><dd>Drag a slider or type a number of megabytes and see the estimate move. Or pick a quality level and let the size follow. Presets cover WhatsApp, Telegram, Discord, Email (25 MB), Instagram and Reels, TikTok, X, YouTube Shorts and Messages.</dd></div>
          <div><dt>Batch compress, and watch the total grow</dt><dd>Add as many videos as you like and compress them in one queue, with progress and a cancel button. A counter keeps the running total of space you saved, such as &ldquo;You saved 3.4 GB&rdquo;.</dd></div>
          <div><dt>Compare before you save</dt><dd>See the original and the compressed video side by side, with both file sizes, so you can judge the quality yourself.</dd></div>
          <div><dt>H.264 for compatibility, HEVC for smaller files</dt><dd>H.264 plays almost everywhere. HEVC makes a smaller file at the same quality, and plays on recent phones, tablets and computers. You choose.</dd></div>
          <div><dt>Control the details</dt><dd>Lower the resolution, reduce 60 frames per second to 30 or 24, change or mute the audio, strip location and other metadata, and trim the clip, when a size target needs more than one lever.</dd></div>
          <div><dt>Progress you can follow</dt><dd>Compression shows progress and an estimate of the time left, and you can cancel at any time.</dd></div>
          <div><dt>Your originals are safe</dt><dd>Shrinkly always writes a new file. After a save it can offer to delete the original, and only deletes it if you confirm.</dd></div>
        </dl>
      </div>
    </div>
  </section>

  <section class="section" id="formats" aria-labelledby="h-formats">
    <div class="wrap">
      <h2 id="h-formats">Opens more than iOS does</h2>
      <div class="section-body">
        <p>Videos from phones, cameras, screen recordings, downloads and old drives come in many containers. Shrinkly reads them all with the same engine and saves a file that plays on your Apple devices and in the apps you send to.</p>
        <div class="table-wrap">
          <table class="formats">
            <caption>What Shrinkly can open and what it saves</caption>
            <tbody>
              <tr><th scope="row">Plays natively in iOS</th><td>MP4, MOV, M4V, 3GP, HEVC video, Live Photo video, slo-mo and Cinematic clips, ProRes MOV</td></tr>
              <tr><th scope="row">Opened by the built-in FFmpeg</th><td>MKV, WebM, AVI, WMV, ASF, FLV, MPG and MPEG, VOB, TS, M2TS and MTS, OGV, DV, AV1 (decode), VP8 and VP9</td></tr>
              <tr><th scope="row">Saved as</th><td>MP4 or MOV, with H.264 or HEVC video and AAC audio</td></tr>
              <tr><th scope="row">Cannot be processed</th><td>Files protected by DRM (such as store purchases and rentals), and encrypted files that need a password</td></tr>
            </tbody>
          </table>
        </div>
        <p class="small">Which files play in your other apps depends on those apps. The built-in format reader is open-source software, see <a href="licenses/">Open-source licences</a>.</p>
      </div>
    </div>
  </section>

  <section class="section band" id="private" aria-labelledby="h-private">
    <div class="wrap">
      <h2 id="h-private">Your videos never leave your device</h2>
      <div class="section-body">
        <p>Shrinkly has no account and no server that stores your videos. Every frame is processed on your phone or iPad. We do not run analytics of our own.</p>
        <ul class="checks">
          <li>You pick videos with the iOS photo picker, so Shrinkly sees only what you choose</li>
          <li>Saving to your library uses add-only permission</li>
          <li>No upload, no cloud queue, no online converter</li>
          <li>Temporary working files are deleted when a job ends</li>
          <li>No account, no sign-in, no subscription</li>
        </ul>
        <p>The only outside service is the ad network. The <a href="privacy/">privacy policy</a> explains what it collects.</p>
      </div>
    </div>
  </section>

  <section class="section" id="free" aria-labelledby="h-free">
    <div class="wrap">
      <h2 id="h-free">Free, and paid for by ads</h2>
      <div class="section-body">
        <p>Shrinkly has no subscription and no in-app purchase. Ads from Google AdMob pay for it, and they appear in two places.</p>
        <div class="split">
          <div>
            <h3>Where you will see ads</h3>
            <ul>
              <li>A banner on the Home screen. Never over the controls you use to compress.</li>
              <li>One short rewarded video before you save or share. You choose whether to watch it, and a batch needs just one.</li>
            </ul>
          </div>
          <div>
            <h3>When no ad is available</h3>
            <ul>
              <li>The export goes ahead for free.</li>
              <li>This happens, for example, when you are offline.</li>
            </ul>
          </div>
        </div>
        <p>Where the law asks for it, the app shows a consent form from Google before personalised ads, and iOS may ask whether the app may track you. Shrinkly itself runs no analytics, and the only tracking that can happen is through Google's ad software, and only if you allow it. You can say no to the iOS prompt and still use everything. Settings has an Ad privacy choices row where one is required.</p>
      </div>
    </div>
  </section>

  <section class="section faq band" id="faq" aria-labelledby="h-faq">
    <div class="wrap">
      <h2 id="h-faq">Questions</h2>
      <div class="section-body">
{faq_html}
      </div>
    </div>
  </section>
</main>
""" + footer("")
    (OUT / "index.html").write_text(body, encoding="utf-8")


# ----------------------------------------------------------------------------- support
def build_support():
    title = "Support | Video Compressor: Shrinkly"
    desc = "Get help with Shrinkly: contact details, and answers about hitting a size target, why a video cannot be smaller, supported formats, protected video, ads and saving."
    items = [
        ("How do I get a video under a size limit?",
         "<ol><li>Choose the video, or several.</li><li>Open the size options and tap a preset such as WhatsApp or Email, or type the size in MB.</li><li>Check the estimate shown under the slider. If it says the target is too low for the length of the clip, raise the target, lower the resolution, or trim the clip.</li><li>Start. When it finishes, look at the result sizes and use Compare to check the quality, then save or share.</li></ol>"
         "<p>The size you ask for is a target. The real file is usually close to it, and can be a little over or under. If a file must stay below a hard limit, set the target a little below the limit.</p>"),
        ("Why can't my video be made smaller?",
         "<p>A video has a lowest useful size. The file size is roughly the bitrate times the length, so a long video squeezed into a few megabytes ends up with a bitrate so low that the picture turns into blocks. Shrinkly keeps a quality floor instead of giving you an unwatchable file, and tells you when your target is below it.</p>"
         "<p>To go lower, try one or more of these: a lower resolution (720p or 480p), a lower frame rate (30 or 24 instead of 60), HEVC instead of H.264, trimming the clip, muting the audio, or splitting a long video in two. Clips that were already compressed hard, such as videos downloaded from social media, have little left to give.</p>"),
        ("My result is a bit bigger than my target",
         "<p>Size targets are aimed at, not guaranteed to the byte. Complex scenes, a high frame rate and audio can all push the result over. Lower the target a few percent and run it again, or choose a lower resolution. Your original is never changed, so you can try again as often as you like.</p>"),
        ("Which video formats work?",
         "<p>Shrinkly opens MP4, MOV, M4V, 3GP, HEVC and ProRes video that iOS plays by itself, and many formats iOS does not play: MKV, WebM, AVI, WMV, ASF, FLV, MPEG, VOB, TS, M2TS, MTS, OGV, DV and others, through a built-in open-source engine. It saves the result as MP4 or MOV with H.264 or HEVC video and AAC audio.</p>"
         "<p>If a file does not open, write to us with the file extension and, if you can, the program that made it. We cannot promise that every unusual file will open, but we want to know about the ones that do not.</p>"),
        ("Why does it say my video is protected?",
         "<p>Videos bought, rented or downloaded from streaming and download stores are protected by digital rights management (DRM). Only the store's own app can play them, and no other app can read them. Shrinkly cannot process these files, and it does not try to bypass the protection. Videos you recorded yourself, or files without protection, work normally.</p>"),
        ("Why am I asked to watch an ad?",
         "<p>Shrinkly is free, and ads pay for it. Before a save, share or export, the app offers one short video that you choose to watch. A batch of videos needs one ad. If you choose Not now, nothing is saved and you can try again any time. If no ad is available, for example when you are offline or your ad privacy choice does not allow ads, the export goes ahead without one. Compressing and previewing never need an ad.</p>"),
        ("Compressing is slow, or it stops",
         "<p>Long videos, 4K video and HEVC take more time, more memory and more battery, and a warm phone slows down to cool off. Keep Shrinkly open and the screen on until the job is finished, make sure your device has free storage of at least the size of the original, and try a lower resolution if a very large file keeps failing. You can cancel at any time and your original stays as it was.</p>"),
        ("Where did my compressed video go?",
         "<p>If you chose Save to Photos, it is in your photo library, at the end of the Recents album. If you chose Files, it is in the folder you picked. The original is untouched. Shrinkly can offer to delete the original after saving, and only does so if you confirm. Check the new file first.</p>"),
        ("H.264 or HEVC?",
         "<p>H.264 plays almost everywhere, including older phones, computers, TVs and every messaging app. HEVC (also called H.265) gives a smaller file at the same quality, but some older devices, websites and apps cannot play it. If you are not sure, choose H.264. If you need the smallest possible file for an Apple device, choose HEVC.</p>"),
        ("Does it remove my location from the video?",
         "<p>Yes, if you turn on the option to strip location and other metadata in the advanced options. The compressed copy is then written without them. Your original keeps its metadata.</p>"),
        ("I want to change my ad or tracking choice",
         "<p>Open Settings in the app and look for the Ad privacy choices row, which appears where the law requires it. You can also change tracking in iOS Settings under Privacy and Security, then Tracking, and reset your advertising identifier there.</p>"),
        ("I saw an ad that seems wrong",
         "<p>Write to us at the address above. Tell us roughly when and where in the app you saw it and what it showed. A screenshot helps. We block ad categories and advertisers through Google AdMob where we can.</p>"),
        ("I have an idea for a preset or a feature",
         "<p>Send it. We read every message, though we cannot promise to build every idea.</p>"),
    ]
    faq_html = "\n".join(f'          <details><summary>{html.escape(q)}</summary><div class="answer">{a}</div></details>' for q, a in items)
    body = head(title, desc, "support/", root="../") + header("../", "support") + f"""
<main id="main">
  <div class="page">
    <div class="wrap">
      <div class="doc">
        <h1>Support</h1>
        <p class="lede">Write to us and a person will read it.</p>
        <p class="contact-line">{EMAIL_TEXT}</p>
        <p class="small">Select the address to copy it into your mail app.</p>
        <p>We reply by email. A message gets answered faster when it includes:</p>
        <ul>
          <li>your iPhone or iPad model and iOS or iPadOS version</li>
          <li>what you were doing and what happened</li>
          <li>the video's format (for example MKV or MOV), its length and roughly its size</li>
          <li>a screenshot, if it helps</li>
        </ul>
        <p>Shrinkly is not on the App Store yet, so support right now covers questions about the app before it is available.</p>
        <h2>Common questions</h2>
        <div class="faq">
{faq_html}
        </div>
        <h2>Company</h2>
        <p>Ecom Swift LLC<br>30 N Gould St #37906<br>Sheridan, WY 82801<br>United States</p>
        <p>Read the <a href="../privacy/">privacy policy</a>, the <a href="../terms/">terms of use</a> and the <a href="../licenses/">open-source licences</a>.</p>
      </div>
    </div>
  </div>
</main>
""" + footer("../")
    (OUT / "support").mkdir(exist_ok=True)
    (OUT / "support" / "index.html").write_text(body, encoding="utf-8")


# ----------------------------------------------------------------------------- legal (markdown -> html)
URL_RE = re.compile(r"(https?://[^\s<)]+)")
MAIL_RE = re.compile(r"([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})")


def inline(text):
    t = html.escape(text, quote=False)
    t = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", t)

    def url(m):
        u = m.group(1)
        trail = ""
        while u and u[-1] in ".,;":
            trail = u[-1] + trail
            u = u[:-1]
        return f'<a href="{u}" rel="noopener">{u}</a>{trail}'

    t = URL_RE.sub(url, t)
    # email addresses stay as selectable text (no mailto link)
    parts = re.split(r"(<a .*?</a>)", t)
    parts = [p if p.startswith("<a ") else MAIL_RE.sub(r'<span class="email">\1</span>', p) for p in parts]
    return "".join(parts)


def md_to_html(md):
    md = re.sub(r"<!-- DRAFT-NOTICE-START -->.*?<!-- DRAFT-NOTICE-END -->", "", md, flags=re.S)
    out, para, items = [], [], []
    title = ""
    meta_open = False
    seen_h2 = False

    def flush_para():
        nonlocal para
        if para:
            out.append("<p>" + "<br>".join(inline(p) for p in para) + "</p>")
            para = []

    def flush_list():
        nonlocal items
        if items:
            out.append("<ul>" + "".join(f"<li>{inline(i)}</li>" for i in items) + "</ul>")
            items = []

    for raw in md.splitlines():
        line = raw.rstrip()
        if line.startswith("# "):
            flush_para(); flush_list()
            title = line[2:].strip()
            out.append(f"<h1>{html.escape(title)}</h1>")
        elif line.startswith("## "):
            flush_para(); flush_list()
            if meta_open:
                out.append("</div>"); meta_open = False
            seen_h2 = True
            out.append(f"<h2>{inline(line[3:].strip())}</h2>")
        elif line.startswith("- "):
            flush_para()
            items.append(line[2:].strip())
        elif not line.strip():
            flush_para(); flush_list()
        elif line.startswith("**") and title and not seen_h2:
            if not meta_open:
                out.append('<div class="meta">'); meta_open = True
            out.append("<p>" + inline(line) + "</p>")
        else:
            flush_list()
            if meta_open:
                out.append("</div>"); meta_open = False
            para.append(line.strip())
    flush_para(); flush_list()
    if meta_open:
        out.append("</div>")
    return title, "\n".join(out)


def build_legal(src, folder, current_title, desc):
    md = (LEGAL / src).read_text(encoding="utf-8")
    title, content = md_to_html(md)
    page_title = f"{current_title} | {SITE_NAME}"
    body = head(page_title, desc, folder + "/", root="../") + header("../", "") + f"""
<main id="main">
  <div class="page">
    <div class="wrap">
      <article class="doc">
{content}
      </article>
    </div>
  </div>
</main>
""" + footer("../")
    (OUT / folder).mkdir(exist_ok=True)
    (OUT / folder / "index.html").write_text(body, encoding="utf-8")


def build_misc():
    urls = ["", "support/", "privacy/", "terms/", "licenses/"]
    xml = ['<?xml version="1.0" encoding="UTF-8"?>',
           '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">']
    for u in urls:
        xml.append(f"  <url><loc>{BASE}{u}</loc><lastmod>{UPDATED}</lastmod></url>")
    xml.append("</urlset>")
    (OUT / "sitemap.xml").write_text("\n".join(xml) + "\n", encoding="utf-8")
    (OUT / "robots.txt").write_text(
        "# Hosted on GitHub Pages as a project path under /shrinkly/.\n"
        "User-agent: *\nAllow: /\n\n"
        f"Sitemap: {BASE}sitemap.xml\n", encoding="utf-8")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    if OUT != SRC_SITE:  # review build elsewhere: bring the assets along
        shutil.copytree(SRC_SITE / "assets", OUT / "assets", dirs_exist_ok=True)
    build_index()
    build_support()
    build_legal("privacy-policy.md", "privacy", "Privacy Policy",
                "How Video Compressor: Shrinkly handles information: videos are processed on your device and never uploaded, there is no account, and ads come from Google AdMob with your consent where required.")
    build_legal("terms-of-use.md", "terms", "Terms of Use",
                "The terms for using Video Compressor: Shrinkly, a free video compressor supported by ads.")
    build_legal("open-source-licenses.md", "licenses", "Open-source licences",
                "Open-source licences and source code offer for Video Compressor: Shrinkly: FFmpeg under the LGPL 2.1 or later, libvpx, libopus, libvorbis, LAME, libwebp and dav1d.")
    build_misc()
    print("site built in", OUT)


if __name__ == "__main__":
    main()
