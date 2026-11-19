"""Builds the App Store screenshots for the iPhone 6.9 inch display (1290 x 2796) from the CI simulator captures.

Usage: python tools/make_store_shots.py <folder-with-CI-pngs> <output-folder>
  e.g. python tools/make_store_shots.py ci/screenshots design/store/6.9

Inputs: home-filled.png, setup-target.png, setup-presets.png, setup-advanced.png, processing.png, result.png,
compare.png, batch.png, formats.png, settings.png (the `screenshots` artifact of the shrinkly workflow).
Layout and copy live in tools/store_shots_common.py. Missing captures are skipped and listed, never invented.
Needs Pillow and numpy.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import store_shots_common as common  # noqa: E402

W, H = 1290, 2796
OPTS = dict(margin=96, head=136, sub=52, top=150, icon=132, gap=64, shot_w=1086, shot_gap=96, min_shot_top=900,
            radius=92, fit_margin=70, motif_w=600, motif_h=20)

if __name__ == "__main__":
    common.run(sys.argv, W, H, OPTS, "iPhone 6.9 inch")
