# Reference colour cards

Generated artefacts. Do not edit by hand — change the kit profile and re-run:

```bash
python3 tools/make_reference_card.py
```

Patch colours and geometry are read from `assets/kits/*.json`, so the printed
card and the app cannot disagree about the specification.

## Files

| File | Use |
|---|---|
| `DS-CARD-A_v1.0.0.pdf` | The card alone at exact physical size (160 × 50 mm), with registration marks. Print this if you are cutting several. |
| `DS-CARD-A_v1.0.0_A4.pdf` | A4 sheet: the card, a 100 mm scale bar, and the full print and characterisation instructions. **Start here.** |
| `DS-CARD-A_v1.0.0.svg` | Vector source, for inspection on screen. Not for printing. |
| `patch_values_DS-CARD-A_v1.0.0.csv` | Nominal values with empty columns for the measured ones. Fill it in when you characterise a printed card. |

## Printing

1. **100% scale.** No "fit to page", no "shrink to fit".
2. **Matte stock.** Glossy paper produces specular highlights that the app's
   glare gate will reject — correctly, because a blown-out patch carries no
   colour information.
3. **Turn off printer colour enhancement.** Any "photo enhance", "vivid" or
   auto-correct setting alters the patch colours, which is the one thing this
   sheet exists to control.
4. Check the 100 mm scale bar with a ruler, then cut along the black keyline.

The keyline is the card boundary. It is what the operator aligns to the
on-screen guide, so cut on it, not outside it.

## The part that actually matters

**The printed patches are nominal, not measured.**

The values in the PDF are the numbers in the kit profile. They are not the
numbers your printer produced. No consumer printer reproduces sRGB accurately,
so as printed this card carries an unknown colour error — and because the app
calibrates *against* the card, every measurement inherits that error.

This is not a small caveat. It is the difference between a colour target and a
photometric reference.

To make the card a real reference:

1. Measure the eight patches with a spectrophotometer or a characterised
   colorimeter.
2. Record the measured sRGB values in
   `patch_values_DS-CARD-A_v1.0.0.csv`, with the date and instrument.
3. Replace the `expectedSrgb` values in the kit profile with the measured
   values, bump the card's `version`, and set `lastVerifiedDate`.
4. Re-run this generator so the printed card and the profile stay in step.

Until that is done, the card is a **geometry target and a consistency aid**: it
still makes measurements from one device comparable with measurements from
another under the same conditions, which is most of the value. It is not a
photometric standard, and nothing measured against it should be described as
absolute colour. See `docs/LIMITATIONS.md`.

A card is also a consumable. Replace it when it is stained, creased or
sun-bleached, and keep it clear of reagents — contaminate it and every later
measurement is affected.

## Do not display this on a screen

Showing the card on a monitor or a second phone instead of printing it will not
work, for four independent reasons:

- a backlit emissive display has a different gamut and white point from a
  reflective print;
- it is not in the same plane or the same illumination as the sample, which is
  the entire premise of the calibration;
- its own brightness setting silently changes the "reference";
- it will produce moiré against the camera sensor.

## Adding a card

Add or edit the `referenceCard` block in a kit profile and re-run the
generator. One `cardId` + `version` must describe exactly one physical card —
the generator refuses to build if two profiles declare the same card
differently, because a measurement taken with an ambiguous card is not
traceable to anything.
