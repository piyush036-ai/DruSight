#!/usr/bin/env python3
"""Generate the printable DruSight reference colour card.

The card is the measurement reference for the whole system: the app estimates
the camera-and-illumination colour transform by comparing what it sees on
these patches against the values the kit profile declares. Nothing downstream
means anything without it.

Patch colours and geometry are read from the kit profile JSON, so the printed
card and the app can never disagree about the specification. Run this again
after changing a profile's reference card.

Outputs, per card, into reference_cards/:
    <card>_<version>.pdf              the card alone, at exact physical size
    <card>_<version>_A4.pdf           A4 sheet: card, scale bar, instructions
    <card>_<version>.svg              vector source for inspection on screen
    patch_values_<card>_<version>.csv the nominal values, for the person who
                                      measures the printed result

Usage:
    python3 tools/make_reference_card.py
    python3 tools/make_reference_card.py --width-mm 200
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from pdf_writer import Page, mm, write_pdf  # noqa: E402

A4_W_MM, A4_H_MM = 210.0, 297.0


def load_cards(kits_dir: Path) -> dict[str, tuple[dict, list[str]]]:
    """Returns {card key: (card spec, kit ids that use it)}.

    Several kit profiles may share one card; it is generated once and the
    profiles that reference it are listed on the print sheet.
    """
    manifest = json.loads((kits_dir / "manifest.json").read_text())
    cards: dict[str, tuple[dict, list[str]]] = {}

    for filename in manifest["profiles"]:
        profile = json.loads((kits_dir / filename).read_text())
        card = profile["referenceCard"]
        key = f"{card['cardId']}_v{card['version']}"
        if key in cards:
            existing_card, kit_ids = cards[key]
            if existing_card != card:
                raise SystemExit(
                    f"Card {key} is defined differently by two profiles. "
                    "A card id and version must describe exactly one "
                    "physical card, or measurements taken with it are "
                    "ambiguous."
                )
            kit_ids.append(profile["kitId"])
        else:
            cards[key] = (card, [profile["kitId"]])
    return cards


def draw_card(
    page: Page,
    card: dict,
    x0: float,
    y0: float,
    w: float,
    h: float,
) -> None:
    """Draws the card with its origin at (x0, y0), PDF coordinates (y up).

    The profile's patch geometry is expressed in image convention, with y
    measured DOWNWARD from the card's top edge, because that is how the
    detector maps it onto a captured frame. PDF measures y upward, so every
    patch is flipped here. Getting this wrong would print a card whose rows
    are swapped relative to the specification, and the app would sample the
    grey ramp where it expected the primaries.
    """
    # White base. The patches are the reference; the surround only has to be
    # neutral and matte.
    page.fill_rect(x0, y0, w, h, (255, 255, 255))

    for patch in card["patches"]:
        r, g, b = patch["expectedSrgb"]
        px = x0 + patch["x"] * w
        pw = patch["w"] * w
        ph = patch["h"] * h
        # Flip from image-down to PDF-up.
        py = y0 + h - (patch["y"] + patch["h"]) * h
        page.fill_rect(px, py, pw, ph, (r, g, b))

    # Identification, in the top margin band. Patch rows start at y=0.10 of
    # the card height, so this band is never sampled.
    page.text(
        x0 + 0.0125 * w,
        y0 + h - mm(3.4),
        f"{card['cardId']}  v{card['version']}   "
        f"PRINT AT 100% ON MATTE STOCK   NOMINAL VALUES - MEASURE BEFORE USE",
        size_pt=4.6,
        rgb8=(40, 40, 40),
    )

    # Boundary keyline. The operator aligns THIS edge to the on-screen guide,
    # so it must sit exactly on the card boundary. The nearest patch pixel is
    # 5.75% of the card width away once the detector's 20% inset is applied,
    # so a hairline cannot contaminate a sample.
    page.stroke_rect(x0, y0, w, h, line_pt=0.3, rgb8=(0, 0, 0))

    # Corner registration marks, drawn outside the keyline so they are removed
    # when the card is cut out.
    tick = mm(3.0)
    gap = mm(1.0)
    for cx, sx in ((x0, -1), (x0 + w, 1)):
        for cy, sy in ((y0, -1), (y0 + h, 1)):
            page.line(cx + sx * gap, cy, cx + sx * (gap + tick), cy, 0.3)
            page.line(cx, cy + sy * gap, cx, cy + sy * (gap + tick), 0.3)


def build_card_pdf(path: Path, card: dict, width_mm: float) -> tuple[float, float]:
    aspect = float(card["aspectRatio"])
    height_mm = width_mm / aspect
    bleed_mm = 6.0  # room for the registration marks

    page = Page(mm(width_mm + 2 * bleed_mm), mm(height_mm + 2 * bleed_mm))
    draw_card(page, card, mm(bleed_mm), mm(bleed_mm), mm(width_mm), mm(height_mm))
    write_pdf(str(path), [page], f"{card['cardId']} v{card['version']}")
    return width_mm, height_mm


def build_a4_sheet(
    path: Path,
    card: dict,
    kit_ids: list[str],
    width_mm: float,
) -> None:
    aspect = float(card["aspectRatio"])
    height_mm = width_mm / aspect

    page = Page(mm(A4_W_MM), mm(A4_H_MM))
    left = (A4_W_MM - width_mm) / 2.0
    card_top = A4_H_MM - 42.0

    page.text(mm(left), mm(A4_H_MM - 22),
              "DruSight reference colour card", size_pt=15)
    page.text(mm(left), mm(A4_H_MM - 30),
              f"{card['cardId']}  version {card['version']}   -   "
              f"used by: {', '.join(kit_ids)}", size_pt=8.5)

    draw_card(page, card, mm(left), mm(card_top - height_mm),
              mm(width_mm), mm(height_mm))

    y = card_top - height_mm - 16.0

    # Scale bar for verifying the printer did not rescale the page.
    page.text(mm(left), mm(y), "Scale check", size_pt=9)
    y -= 6.0
    bar = 100.0
    page.line(mm(left), mm(y), mm(left + bar), mm(y), 0.6)
    for i in range(11):
        tick = 2.0 if i % 5 else 3.5
        page.line(mm(left + i * 10), mm(y), mm(left + i * 10), mm(y + tick), 0.6)
    page.text(mm(left + bar + 3), mm(y - 0.8),
              "this bar must measure exactly 100 mm", size_pt=7.5)
    y -= 12.0

    lines: list[tuple[str, float]] = [
        ("Printing", 10.0),
        ("1. Print at 100% scale. Do not use 'fit to page' or 'shrink to fit'.", 8),
        ("2. Use MATTE stock. Glossy paper produces specular highlights that the", 8),
        ("   app's glare gate will reject.", 8),
        ("3. Disable any 'photo enhance', 'vivid' or auto-correction setting in the", 8),
        ("   printer driver. Those alter the patch colours, which is the one thing", 8),
        ("   this sheet exists to control.", 8),
        ("4. Verify the scale bar above, then cut along the black keyline.", 8),
        ("", 6),
        ("Before you trust a measurement taken with this card", 10.0),
        ("The values printed here are NOMINAL - they are the numbers in the kit", 8),
        ("profile, not the numbers your printer produced. No consumer printer", 8),
        ("reproduces sRGB accurately, so as printed this card carries an unknown", 8),
        ("colour error, and every measurement calibrated against it inherits that", 8),
        ("error.", 8),
        ("", 6),
        ("To make the card a real reference, measure the eight patches with a", 8),
        ("spectrophotometer or a characterised colorimeter, and replace the", 8),
        ("expectedSrgb values in the kit profile with the measured values. Record", 8),
        ("the measurement date in lastVerifiedDate. Until that is done, treat the", 8),
        ("card as a geometry target and a consistency aid, not as a photometric", 8),
        ("standard. See docs/LIMITATIONS.md.", 8),
        ("", 6),
        ("Do NOT display this card on a screen instead of printing it. A backlit", 8),
        ("emissive display has a different gamut and white point from a reflective", 8),
        ("print, is not in the same plane or illumination as the sample, and will", 8),
        ("produce moire against the camera sensor.", 8),
        ("", 6),
        ("In the field", 10.0),
        ("Keep the card flat, clean and unfaded, and keep it clear of reagents.", 8),
        ("Place it in the SAME plane and the SAME light as the reaction area, with", 8),
        ("both inside their on-screen guides in one frame.", 8),
        ("Replace the card if it is stained, creased or sun-bleached.", 8),
    ]
    for text, size in lines:
        if text:
            page.text(mm(left), mm(y), text, size_pt=size)
        y -= 4.4 if size <= 8 else 5.8

    page.text(mm(left), mm(12),
              "Presumptive field-test result. Confirmatory laboratory testing "
              "is required.", size_pt=8)

    write_pdf(str(path), [page],
              f"{card['cardId']} v{card['version']} print sheet")


def build_svg(path: Path, card: dict, width_mm: float) -> None:
    aspect = float(card["aspectRatio"])
    height_mm = width_mm / aspect

    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" '
        f'width="{width_mm}mm" height="{height_mm}mm" '
        f'viewBox="0 0 {width_mm} {height_mm}">',
        f'  <title>{card["cardId"]} v{card["version"]}</title>',
        f'  <rect x="0" y="0" width="{width_mm}" height="{height_mm}" '
        f'fill="#ffffff"/>',
    ]
    # SVG uses the same y-down convention as the profile, so no flip here.
    for patch in card["patches"]:
        r, g, b = patch["expectedSrgb"]
        parts.append(
            f'  <rect x="{patch["x"] * width_mm:.4f}" '
            f'y="{patch["y"] * height_mm:.4f}" '
            f'width="{patch["w"] * width_mm:.4f}" '
            f'height="{patch["h"] * height_mm:.4f}" '
            f'fill="#{r:02x}{g:02x}{b:02x}" '
            f'data-patch-id="{patch["id"]}"/>'
        )
    parts.append(
        f'  <rect x="0" y="0" width="{width_mm}" height="{height_mm}" '
        f'fill="none" stroke="#000000" stroke-width="0.1"/>'
    )
    parts.append("</svg>")
    path.write_text("\n".join(parts) + "\n")


def build_patch_csv(path: Path, card: dict) -> None:
    rows = [
        "patch_id,nominal_r,nominal_g,nominal_b,"
        "measured_r,measured_g,measured_b,measured_date,instrument"
    ]
    for patch in card["patches"]:
        r, g, b = patch["expectedSrgb"]
        rows.append(f"{patch['id']},{r},{g},{b},,,,,")
    path.write_text("\n".join(rows) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kits-dir", default="assets/kits", type=Path)
    parser.add_argument("--out-dir", default="reference_cards", type=Path)
    parser.add_argument(
        "--width-mm",
        type=float,
        default=160.0,
        help="Printed card width. Height follows from the profile's "
             "aspectRatio. Default 160 mm fits A4 with margins.",
    )
    args = parser.parse_args()

    args.out_dir.mkdir(parents=True, exist_ok=True)
    cards = load_cards(args.kits_dir)
    if not cards:
        print("No reference cards found in the kit manifest.", file=sys.stderr)
        return 1

    for key, (card, kit_ids) in sorted(cards.items()):
        w, h = build_card_pdf(args.out_dir / f"{key}.pdf", card, args.width_mm)
        build_a4_sheet(args.out_dir / f"{key}_A4.pdf", card, kit_ids,
                       args.width_mm)
        build_svg(args.out_dir / f"{key}.svg", card, args.width_mm)
        build_patch_csv(args.out_dir / f"patch_values_{key}.csv", card)

        print(
            f"{key}: {len(card['patches'])} patches, "
            f"{w:.1f} x {h:.1f} mm (aspect {card['aspectRatio']}), "
            f"used by {', '.join(kit_ids)}"
        )
    print(f"\nWritten to {args.out_dir}/")
    print("The printed patches are NOMINAL until measured. See "
          f"{args.out_dir}/README.md")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
