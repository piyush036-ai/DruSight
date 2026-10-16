"""A minimal, dependency-free PDF writer.

Only what a reference card needs: filled rectangles, hairline strokes and
small text. Written by hand rather than pulled from a library because this
tool must run anywhere with a bare Python 3, and because a reference card is
exactly the kind of artefact where an unexamined dependency silently
resampling or colour-managing the output would ruin it.

Colour is emitted as DeviceRGB. See reference_cards/README.md for why that
still does not make the printed patches trustworthy without measurement.
"""

from __future__ import annotations

MM_TO_PT = 72.0 / 25.4


def mm(value: float) -> float:
    """Millimetres to PostScript points."""
    return value * MM_TO_PT


class Page:
    """Accumulates content-stream operators for one page."""

    def __init__(self, width_pt: float, height_pt: float) -> None:
        self.width = width_pt
        self.height = height_pt
        self._ops: list[str] = []

    def fill_rect(
        self,
        x: float,
        y: float,
        w: float,
        h: float,
        rgb8: tuple[int, int, int],
    ) -> None:
        """Filled rectangle. `rgb8` is 0-255 sRGB, emitted as DeviceRGB."""
        r, g, b = (c / 255.0 for c in rgb8)
        self._ops.append(
            f"{r:.6f} {g:.6f} {b:.6f} rg "
            f"{x:.4f} {y:.4f} {w:.4f} {h:.4f} re f"
        )

    def stroke_rect(
        self,
        x: float,
        y: float,
        w: float,
        h: float,
        line_pt: float = 0.25,
        rgb8: tuple[int, int, int] = (0, 0, 0),
    ) -> None:
        r, g, b = (c / 255.0 for c in rgb8)
        self._ops.append(
            f"{r:.6f} {g:.6f} {b:.6f} RG {line_pt:.4f} w "
            f"{x:.4f} {y:.4f} {w:.4f} {h:.4f} re S"
        )

    def line(
        self,
        x1: float,
        y1: float,
        x2: float,
        y2: float,
        line_pt: float = 0.25,
        rgb8: tuple[int, int, int] = (0, 0, 0),
    ) -> None:
        r, g, b = (c / 255.0 for c in rgb8)
        self._ops.append(
            f"{r:.6f} {g:.6f} {b:.6f} RG {line_pt:.4f} w "
            f"{x1:.4f} {y1:.4f} m {x2:.4f} {y2:.4f} l S"
        )

    def text(
        self,
        x: float,
        y: float,
        value: str,
        size_pt: float = 8.0,
        rgb8: tuple[int, int, int] = (0, 0, 0),
        font: str = "F1",
    ) -> None:
        r, g, b = (c / 255.0 for c in rgb8)
        self._ops.append(
            f"BT {r:.6f} {g:.6f} {b:.6f} rg /{font} {size_pt:.2f} Tf "
            f"{x:.4f} {y:.4f} Td ({_escape(value)}) Tj ET"
        )

    def content(self) -> str:
        return "\n".join(self._ops)


def _escape(value: str) -> str:
    """PDF string escaping, and a hard stop on non-Latin-1 text.

    The base-14 fonts are Latin-1 only. Silently dropping a character would
    produce a card whose printed label does not match its filename, so this
    raises instead.
    """
    try:
        value.encode("latin-1")
    except UnicodeEncodeError as exc:
        raise ValueError(
            f"Text {value!r} is not representable in the Latin-1 base font."
        ) from exc
    return value.replace("\\", r"\\").replace("(", r"\(").replace(")", r"\)")


def write_pdf(path: str, pages: list[Page], title: str) -> None:
    """Serialises pages to a PDF 1.4 file with a correct xref table."""
    objects: list[bytes] = []

    def add(body: str | bytes) -> int:
        objects.append(body.encode("latin-1") if isinstance(body, str) else body)
        return len(objects)  # 1-based object number

    # Object numbering is fixed up front so /Kids and /Parent can reference
    # each other.
    n_catalog = 1
    n_pages = 2
    n_font = 3
    first_page_obj = 4

    page_obj_numbers = [first_page_obj + 2 * i for i in range(len(pages))]
    kids = " ".join(f"{n} 0 R" for n in page_obj_numbers)

    add(f"<< /Type /Catalog /Pages {n_pages} 0 R >>")
    add(f"<< /Type /Pages /Count {len(pages)} /Kids [{kids}] >>")
    add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica "
        "/Encoding /WinAnsiEncoding >>")

    for i, page in enumerate(pages):
        content = page.content().encode("latin-1")
        content_obj = page_obj_numbers[i] + 1
        add(
            f"<< /Type /Page /Parent {n_pages} 0 R "
            f"/MediaBox [0 0 {page.width:.4f} {page.height:.4f}] "
            f"/Resources << /Font << /F1 {n_font} 0 R >> >> "
            f"/Contents {content_obj} 0 R >>"
        )
        add(
            b"<< /Length " + str(len(content)).encode() + b" >>\nstream\n"
            + content + b"\nendstream"
        )

    out = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    offsets: list[int] = []
    for number, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += f"{number} 0 obj\n".encode("latin-1") + body + b"\nendobj\n"

    xref_at = len(out)
    out += f"xref\n0 {len(objects) + 1}\n".encode("latin-1")
    out += b"0000000000 65535 f \n"
    for offset in offsets:
        out += f"{offset:010d} 00000 n \n".encode("latin-1")

    out += (
        f"trailer\n<< /Size {len(objects) + 1} /Root {n_catalog} 0 R "
        f"/Info << /Title ({_escape(title)}) "
        f"/Producer (DruSight reference-card generator) >> >>\n"
        f"startxref\n{xref_at}\n%%EOF\n"
    ).encode("latin-1")

    with open(path, "wb") as handle:
        handle.write(out)
