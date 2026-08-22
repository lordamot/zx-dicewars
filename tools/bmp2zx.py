#!/usr/bin/env python3
"""Convert a BMP image into ZX Spectrum screen format (and back).

Usage:
    bmp2zx.py INPUT.bmp --scr OUT.scr [--bmp PREVIEW.bmp] [--dither MODE]
    bmp2zx.py INPUT.scr --from-scr --bmp OUT.bmp

The source must be exactly 256x192 pixels. Colours are reduced to the
15-colour ZX palette and then to the Spectrum's "two colours per 8x8
cell" attribute rule; --bmp writes the result back out as a plain BMP so
the colour conversion can be inspected before it becomes screen bytes.
"""

import argparse
import struct
import sys
from pathlib import Path

WIDTH = 256
HEIGHT = 192
CELLS_X = WIDTH // 8
CELLS_Y = HEIGHT // 8
BITMAP_SIZE = 6144
ATTR_SIZE = 768
SCR_SIZE = BITMAP_SIZE + ATTR_SIZE

# Colour component level for normal and bright attributes. Matches the
# palette used by Fuse/ZEsarUX; see .claude/docs/tools/bmp.md.
NORMAL_LEVEL = 0xD7
BRIGHT_LEVEL = 0xFF

# Perceptual-ish weighting for the RGB distance used by all colour matching.
WEIGHT_R, WEIGHT_G, WEIGHT_B = 2, 4, 3

BAYER8 = [
    [0, 32, 8, 40, 2, 34, 10, 42],
    [48, 16, 56, 24, 50, 18, 58, 26],
    [12, 44, 4, 36, 14, 46, 6, 38],
    [60, 28, 52, 20, 62, 30, 54, 22],
    [3, 35, 11, 43, 1, 33, 9, 41],
    [51, 19, 59, 27, 49, 17, 57, 25],
    [15, 47, 7, 39, 13, 45, 5, 37],
    [63, 31, 55, 23, 61, 29, 53, 21],
]


def build_palette():
    """16 entries: index = bright * 8 + colour (colour bits: 1=blue 2=red 4=green)."""
    palette = []
    for bright in (0, 1):
        level = BRIGHT_LEVEL if bright else NORMAL_LEVEL
        for colour in range(8):
            palette.append(
                (
                    level if colour & 2 else 0,
                    level if colour & 4 else 0,
                    level if colour & 1 else 0,
                )
            )
    return palette


PALETTE = build_palette()


def colour_distance(a, b):
    dr = a[0] - b[0]
    dg = a[1] - b[1]
    db = a[2] - b[2]
    return WEIGHT_R * dr * dr + WEIGHT_G * dg * dg + WEIGHT_B * db * db


def screen_offset(x_char, y_pixel):
    """Byte offset of a pixel row inside the 6144-byte ZX bitmap area."""
    return ((y_pixel & 0xC0) << 5) | ((y_pixel & 0x07) << 8) | ((y_pixel & 0x38) << 2) | x_char


# --------------------------------------------------------------------------
# BMP reading / writing
# --------------------------------------------------------------------------


def _mask_shift_size(mask):
    if mask == 0:
        return 0, 0
    shift = (mask & -mask).bit_length() - 1
    return shift, (mask >> shift).bit_length()


def _scale_component(value, bits):
    if bits == 0:
        return 0
    if bits == 8:
        return value
    maximum = (1 << bits) - 1
    return (value * 255 + maximum // 2) // maximum


def read_bmp(path):
    """Read a BMP file into a top-down list of rows of (r, g, b) tuples."""
    data = path.read_bytes()
    if len(data) < 54 or data[0:2] != b"BM":
        sys.exit(f"error: {path} is not a BMP file")

    pixel_offset = struct.unpack_from("<I", data, 10)[0]
    dib_size = struct.unpack_from("<I", data, 14)[0]
    if dib_size < 40:
        sys.exit(f"error: {path} uses an unsupported {dib_size}-byte BMP header (need 40 or larger)")

    width, height = struct.unpack_from("<ii", data, 18)
    bpp = struct.unpack_from("<H", data, 28)[0]
    compression = struct.unpack_from("<I", data, 30)[0]
    colours_used = struct.unpack_from("<I", data, 46)[0]

    if compression not in (0, 3):
        sys.exit(f"error: {path} uses BMP compression {compression}; only uncompressed BMPs are supported")

    top_down = height < 0
    height = abs(height)

    masks = None
    if compression == 3:
        if dib_size >= 56:
            masks = struct.unpack_from("<IIII", data, 14 + 40)
        else:
            masks = struct.unpack_from("<III", data, 14 + dib_size) + (0,)

    palette = []
    if bpp <= 8:
        count = colours_used or (1 << bpp)
        base = 14 + dib_size
        for i in range(count):
            b, g, r = data[base + i * 4], data[base + i * 4 + 1], data[base + i * 4 + 2]
            palette.append((r, g, b))

    stride = ((bpp * width + 31) // 32) * 4
    rows = []
    for row_index in range(height):
        src_row = row_index if top_down else height - 1 - row_index
        start = pixel_offset + src_row * stride
        raw = data[start : start + stride]
        if len(raw) < stride:
            sys.exit(f"error: {path} is truncated (pixel data ends early)")
        rows.append(_decode_row(raw, width, bpp, palette, masks, path))
    return width, height, rows


def _decode_row(raw, width, bpp, palette, masks, path):
    row = []
    if bpp == 24:
        for x in range(width):
            b, g, r = raw[x * 3], raw[x * 3 + 1], raw[x * 3 + 2]
            row.append((r, g, b))
    elif bpp == 32 and masks is None:
        for x in range(width):
            b, g, r = raw[x * 4], raw[x * 4 + 1], raw[x * 4 + 2]
            row.append((r, g, b))
    elif bpp in (16, 32) and masks is not None:
        step = bpp // 8
        shifts = [_mask_shift_size(m) for m in masks[:3]]
        for x in range(width):
            value = int.from_bytes(raw[x * step : x * step + step], "little")
            row.append(
                tuple(
                    _scale_component((value & masks[i]) >> shifts[i][0], shifts[i][1])
                    for i in range(3)
                )
            )
    elif bpp in (1, 4, 8):
        per_byte = 8 // bpp
        mask = (1 << bpp) - 1
        for x in range(width):
            byte = raw[x // per_byte]
            shift = (per_byte - 1 - (x % per_byte)) * bpp
            index = (byte >> shift) & mask
            if index >= len(palette):
                sys.exit(f"error: {path} references palette entry {index} that is not in the file")
            row.append(palette[index])
    else:
        sys.exit(f"error: {path} uses unsupported {bpp} bits per pixel")
    return row


def write_bmp(path, rows):
    """Write a top-down list of rows of (r, g, b) as a 24-bit bottom-up BMP."""
    height = len(rows)
    width = len(rows[0])
    stride = ((width * 3 + 3) // 4) * 4
    padding = b"\x00" * (stride - width * 3)

    pixels = bytearray()
    for row in reversed(rows):
        for r, g, b in row:
            pixels += bytes((b, g, r))
        pixels += padding

    header = struct.pack("<2sIHHI", b"BM", 14 + 40 + len(pixels), 0, 0, 14 + 40)
    dib = struct.pack("<IiiHHIIiiII", 40, width, height, 1, 24, 0, len(pixels), 2835, 2835, 0, 0)
    path.write_bytes(header + dib + bytes(pixels))


# --------------------------------------------------------------------------
# Conversion
# --------------------------------------------------------------------------


def choose_cell_colours(cell_pixels):
    """Pick (bright, ink, paper) minimising total colour error for one 8x8 cell."""
    distances = [[colour_distance(px, entry) for entry in PALETTE] for px in cell_pixels]

    best_cost = None
    best = (0, 0, 0)
    for bright in (0, 1):
        base = bright * 8
        for first in range(8):
            for second in range(first, 8):
                a = base + first
                b = base + second
                cost = 0
                for row in distances:
                    da = row[a]
                    db = row[b]
                    cost += da if da < db else db
                if best_cost is None or cost < best_cost:
                    best_cost = cost
                    best = (bright, first, second)

    bright, first, second = best
    if first == second:
        return bright, first, second

    # Whichever colour claims more pixels becomes paper, so ink marks the detail.
    base = bright * 8
    count_first = sum(1 for row in distances if row[base + first] <= row[base + second])
    if count_first > len(distances) - count_first:
        return bright, second, first
    return bright, first, second


def count_source_colours(cell_pixels):
    """How many distinct ZX palette colours the cell wanted before the 2-colour rule."""
    seen = set()
    for px in cell_pixels:
        seen.add(min(range(16), key=lambda i: colour_distance(px, PALETTE[i])))
    return len(seen)


def convert(rows, dither):
    """Return (scr_bytes, preview_rows, cells_over_two_colours)."""
    bitmap = bytearray(BITMAP_SIZE)
    attributes = bytearray(ATTR_SIZE)
    preview = [[(0, 0, 0)] * WIDTH for _ in range(HEIGHT)]

    cell_colours = {}
    clashes = 0
    for cy in range(CELLS_Y):
        for cx in range(CELLS_X):
            pixels = [rows[cy * 8 + y][cx * 8 + x] for y in range(8) for x in range(8)]
            bright, ink, paper = choose_cell_colours(pixels)
            cell_colours[(cx, cy)] = (bright, ink, paper)
            attributes[cy * 32 + cx] = (bright << 6) | (paper << 3) | ink
            if count_source_colours(pixels) > 2:
                clashes += 1

    errors = [[(0.0, 0.0, 0.0)] * WIDTH for _ in range(HEIGHT)] if dither == "floyd" else None

    for y in range(HEIGHT):
        for x in range(WIDTH):
            bright, ink, paper = cell_colours[(x // 8, y // 8)]
            base = bright * 8
            ink_rgb = PALETTE[base + ink]
            paper_rgb = PALETTE[base + paper]
            source = rows[y][x]

            if ink == paper:
                use_ink = False
            elif dither == "floyd":
                err = errors[y][x]
                wanted = (source[0] + err[0], source[1] + err[1], source[2] + err[2])
                use_ink = colour_distance(wanted, ink_rgb) < colour_distance(wanted, paper_rgb)
                chosen = ink_rgb if use_ink else paper_rgb
                _diffuse(errors, x, y, (wanted[0] - chosen[0], wanted[1] - chosen[1], wanted[2] - chosen[2]))
            elif dither == "bayer":
                use_ink = _bayer_pick(source, ink_rgb, paper_rgb, x, y)
            else:
                use_ink = colour_distance(source, ink_rgb) < colour_distance(source, paper_rgb)

            if use_ink:
                offset = screen_offset(x // 8, y)
                bitmap[offset] |= 0x80 >> (x % 8)
            preview[y][x] = ink_rgb if use_ink else paper_rgb

    return bytes(bitmap) + bytes(attributes), preview, clashes


def _bayer_pick(source, ink_rgb, paper_rgb, x, y):
    """Ordered dithering: threshold the pixel's position along the paper->ink axis."""
    axis = tuple(ink_rgb[i] - paper_rgb[i] for i in range(3))
    length = WEIGHT_R * axis[0] ** 2 + WEIGHT_G * axis[1] ** 2 + WEIGHT_B * axis[2] ** 2
    if length == 0:
        return False
    projection = (
        WEIGHT_R * (source[0] - paper_rgb[0]) * axis[0]
        + WEIGHT_G * (source[1] - paper_rgb[1]) * axis[1]
        + WEIGHT_B * (source[2] - paper_rgb[2]) * axis[2]
    ) / length
    threshold = (BAYER8[y % 8][x % 8] + 0.5) / 64.0
    return projection > threshold


def _diffuse(errors, x, y, error):
    for dx, dy, weight in ((1, 0, 7 / 16), (-1, 1, 3 / 16), (0, 1, 5 / 16), (1, 1, 1 / 16)):
        nx, ny = x + dx, y + dy
        if 0 <= nx < WIDTH and 0 <= ny < HEIGHT:
            current = errors[ny][nx]
            errors[ny][nx] = tuple(current[i] + error[i] * weight for i in range(3))


def scr_to_rows(scr):
    """Render a 6912-byte screen into a top-down list of rows of (r, g, b)."""
    rows = []
    for y in range(HEIGHT):
        row = []
        for cx in range(CELLS_X):
            byte = scr[screen_offset(cx, y)]
            attribute = scr[BITMAP_SIZE + (y // 8) * 32 + cx]
            base = ((attribute >> 6) & 1) * 8
            ink_rgb = PALETTE[base + (attribute & 7)]
            paper_rgb = PALETTE[base + ((attribute >> 3) & 7)]
            for bit in range(8):
                row.append(ink_rgb if (byte >> (7 - bit)) & 1 else paper_rgb)
        rows.append(row)
    return rows


# --------------------------------------------------------------------------
# Entry point
# --------------------------------------------------------------------------


def check_output(path, force):
    if path.exists() and not force:
        sys.exit(f"error: {path} already exists (use --force to overwrite)")


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("input", type=Path, help="source .bmp (or .scr with --from-scr)")
    parser.add_argument("--scr", type=Path, help="write the 6912-byte ZX screen here")
    parser.add_argument("--bmp", type=Path, help="write the converted image back out as a BMP")
    parser.add_argument(
        "--dither",
        choices=("auto", "none", "bayer", "floyd"),
        default="none",
        help="how to shade pixels between a cell's two colours (default: none; "
        "auto picks none for already-ZX-coloured art, bayer for everything else)",
    )
    parser.add_argument("--from-scr", action="store_true", help="input is a 6912-byte screen, not a BMP")
    parser.add_argument("--force", action="store_true", help="overwrite existing output files")
    args = parser.parse_args()

    if not args.input.is_file():
        sys.exit(f"error: {args.input} not found")
    if not args.scr and not args.bmp:
        sys.exit("error: nothing to do — pass --scr and/or --bmp")

    if args.from_scr:
        if args.scr:
            sys.exit("error: --scr makes no sense with --from-scr")
        scr = args.input.read_bytes()
        if len(scr) != SCR_SIZE:
            sys.exit(f"error: {args.input} is {len(scr)} bytes, expected {SCR_SIZE}")
        check_output(args.bmp, args.force)
        write_bmp(args.bmp, scr_to_rows(scr))
        print(f"{args.input} -> {args.bmp} ({WIDTH}x{HEIGHT} BMP)")
        return

    if args.scr:
        check_output(args.scr, args.force)
    if args.bmp:
        check_output(args.bmp, args.force)

    width, height, rows = read_bmp(args.input)
    if (width, height) != (WIDTH, HEIGHT):
        sys.exit(
            f"error: {args.input} is {width}x{height}, expected {WIDTH}x{HEIGHT} "
            "(one ZX Spectrum screen)"
        )

    dither = args.dither
    if dither == "auto":
        # Already-ZX-coloured art (e.g. a round-tripped screen) converts
        # losslessly without dithering; for anything else ordered dithering
        # both looks best on the Spectrum and packs smallest under
        # tools/openit_rle.py -- see .claude/docs/tools/bmp.md.
        palette = set(PALETTE)
        exact = all(px in palette for row in rows for px in row)
        dither = "none" if exact else "bayer"
        print(f"dither: auto -> {dither}")

    scr, preview, clashes = convert(rows, dither)

    if args.scr:
        args.scr.write_bytes(scr)
        print(f"{args.input} -> {args.scr} ({SCR_SIZE} bytes)")
    if args.bmp:
        write_bmp(args.bmp, preview)
        print(f"{args.input} -> {args.bmp} ({WIDTH}x{HEIGHT} BMP)")

    total = CELLS_X * CELLS_Y
    print(f"dither: {dither}; {clashes}/{total} cells lost colours to the 2-per-cell rule")


if __name__ == "__main__":
    main()
