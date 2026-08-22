#!/usr/bin/env python3
"""Prepare a photo for the ZX screen converter: crop, resize to 256x192,
and pre-process for 1-bit dithering.

Usage:
    photo2bmp.py INPUT.jpg --out OUT.bmp [--top N] [--height N] [--force]
                 [--color] [--gamma F] [--unsharp PCT]

Crops the full width of the source starting --top pixels down, --height
pixels tall (default: width*3/4 for the 4:3 screen) and resizes to
256x192. By default the result is grayscale, autocontrasted, unsharp-
masked (local contrast is what makes faces survive Floyd dithering at
256x192) and gamma-lifted - tuned for tools/bmp2zx.py --dither floyd.
--color skips the grayscale conversion.

Needs Pillow (the only tool here that does; this is asset preparation,
not part of `make build` - the BMPs in src/res/screens/ are the
committed source art). See `make screens`.
"""

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image, ImageFilter, ImageOps
except ImportError:
    sys.exit("error: Pillow is required (pip install Pillow)")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("input", type=Path)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--top", type=int, default=0, help="crop offset from the top")
    ap.add_argument("--height", type=int, default=0,
                    help="crop height (default: width*3/4)")
    ap.add_argument("--color", action="store_true",
                    help="keep colour (default: grayscale for clean dithering)")
    ap.add_argument("--gamma", type=float, default=0.8)
    ap.add_argument("--unsharp", type=int, default=220,
                    help="unsharp mask strength in percent (0 = off)")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    if args.out.exists() and not args.force:
        sys.exit(f"error: {args.out} exists (use --force)")
    im = Image.open(args.input).convert("RGB")
    w, h = im.size
    ch = args.height or w * 3 // 4
    top = max(0, min(args.top, h - ch))
    im = im.crop((0, top, w, top + ch)).resize((256, 192), Image.LANCZOS)
    if not args.color:
        im = im.convert("L")
    im = ImageOps.autocontrast(im, cutoff=2)
    if args.unsharp:
        im = im.filter(ImageFilter.UnsharpMask(radius=3, percent=args.unsharp,
                                               threshold=2))
    if args.gamma != 1.0:
        g = args.gamma
        im = im.point(lambda v: int(((v / 255.0) ** g) * 255 + 0.5))
    im = im.convert("RGB")
    args.out.parent.mkdir(parents=True, exist_ok=True)
    im.save(args.out, "BMP")
    print(f"{args.out}: 256x192 from {w}x{h} (top={top}, height={ch})")


if __name__ == "__main__":
    main()
