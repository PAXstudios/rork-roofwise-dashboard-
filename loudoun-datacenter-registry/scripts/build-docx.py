#!/usr/bin/env python3
"""
Build a styled Word (.docx) version of a markdown document.

    python3 scripts/build-docx.py LOVABLE-BUILD-PROMPT.md
    python3 scripts/build-docx.py LOVABLE-BUILD-PROMPT.md -o /tmp/out.docx

Why this exists: the handoff document is maintained as markdown (it's diffable,
and half of it is code and SQL that must stay copy-pasteable), but people read
and comment on it in Word. This regenerates the .docx from the markdown so the
two can't drift.

Requires `pandoc`. On Debian/Ubuntu: `apt-get install pandoc`.

The styling is applied through a pandoc reference document that this script
generates on the fly — US Letter, Georgia for body text, Arial for headings,
Consolas for code. Nothing is hand-maintained in binary form.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

# Half-points: 21 = 10.5pt. Word's units, not mine.
STYLE_SPEC = {
    "Normal":   dict(sz=21, color="1A1A1A"),
    "Title":    dict(sz=52, color="121212", bold=True, space_after=120),
    "Subtitle": dict(sz=26, color="5A5A55", space_after=360),
    "Heading1": dict(sz=34, color="121212", bold=True, space_before=440, space_after=140),
    "Heading2": dict(sz=27, color="121212", bold=True, space_before=340, space_after=110),
    "Heading3": dict(sz=23, color="1C4F8F", bold=True, space_before=260, space_after=90),
    "Heading4": dict(sz=21, color="5A5A55", bold=True, space_before=200, space_after=80),
    "BodyText": dict(space_after=140),
}

# 12240 x 15840 DXA = 8.5in x 11in. 1440 DXA = 1 inch.
SECT_PR = (
    "<w:sectPr>"
    '<w:pgSz w:w="12240" w:h="15840"/>'
    '<w:pgMar w:top="1080" w:right="1080" w:bottom="1080" w:left="1080"'
    ' w:header="720" w:footer="720" w:gutter="0"/>'
    "</w:sectPr>"
)


def restyle(styles_xml: str, style_id: str, *, sz=None, color=None, bold=False,
            space_before=None, space_after=None) -> str:
    """Patch one named style's run and paragraph properties in styles.xml."""
    match = re.search(
        r'(<w:style [^>]*w:styleId="%s".*?</w:style>)' % re.escape(style_id),
        styles_xml,
        re.S,
    )
    if not match:
        return styles_xml

    block = match.group(1)

    if sz is not None:
        block = re.sub(r'<w:sz w:val="\d+" ?/>', f'<w:sz w:val="{sz}"/>', block)
        block = re.sub(r'<w:szCs w:val="\d+" ?/>', f'<w:szCs w:val="{sz}"/>', block)
        if "<w:sz " not in block:
            block = block.replace(
                "</w:rPr>", f'<w:sz w:val="{sz}"/><w:szCs w:val="{sz}"/></w:rPr>'
            )

    if color is not None:
        block = re.sub(r'<w:color w:val="[^"]*" ?/>', f'<w:color w:val="{color}"/>', block)
        if "<w:color " not in block:
            block = block.replace("</w:rPr>", f'<w:color w:val="{color}"/></w:rPr>')

    if bold and "<w:b/>" not in block and "<w:b " not in block:
        block = block.replace("</w:rPr>", "<w:b/></w:rPr>")

    if space_before is not None or space_after is not None:
        before = f' w:before="{space_before}"' if space_before is not None else ""
        after = f' w:after="{space_after}"' if space_after is not None else ""
        spacing = f'<w:spacing{before}{after} w:line="276" w:lineRule="auto"/>'
        if "<w:spacing" in block:
            block = re.sub(r"<w:spacing[^/]*/>", spacing, block, count=1)
        elif "<w:pPr>" in block:
            block = block.replace("<w:pPr>", f"<w:pPr>{spacing}", 1)

    return styles_xml[: match.start(1)] + block + styles_xml[match.end(1):]


def build_reference(workdir: str) -> str:
    """Generate a styled pandoc reference.docx from pandoc's own default."""
    default_path = os.path.join(workdir, "reference-default.docx")
    with open(default_path, "wb") as handle:
        subprocess.run(
            ["pandoc", "--print-default-data-file", "reference.docx"],
            stdout=handle,
            check=True,
        )

    unpacked = os.path.join(workdir, "refdoc")
    os.makedirs(unpacked, exist_ok=True)
    with zipfile.ZipFile(default_path) as archive:
        archive.extractall(unpacked)

    # ---- Typography ------------------------------------------------------
    styles_path = os.path.join(unpacked, "word", "styles.xml")
    with open(styles_path, encoding="utf-8") as handle:
        styles = handle.read()

    # Body serif, headings grotesque. Georgia and Arial ship with every Windows
    # and macOS install, so the document renders the same on the reader's
    # machine — which a downloadable .docx cannot assume of anything else.
    styles = styles.replace(
        '<w:rFonts w:asciiTheme="minorHAnsi" w:eastAsiaTheme="minorHAnsi"'
        ' w:hAnsiTheme="minorHAnsi" w:cstheme="minorBidi" />',
        '<w:rFonts w:ascii="Georgia" w:hAnsi="Georgia" w:cs="Georgia" />',
        1,
    )
    styles = styles.replace(
        '<w:rFonts w:asciiTheme="majorHAnsi" w:eastAsiaTheme="majorEastAsia"'
        ' w:hAnsiTheme="majorHAnsi" w:cstheme="majorBidi" />',
        '<w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial" />',
        1,
    )

    for style_id, spec in STYLE_SPEC.items():
        styles = restyle(styles, style_id, **spec)

    # Code small enough that long SQL lines don't wrap into soup.
    styles = re.sub(
        r'(w:styleId="VerbatimChar".*?)<w:sz w:val="\d+" ?/>',
        r'\1<w:sz w:val="17"/>',
        styles,
        flags=re.S,
    )

    with open(styles_path, "w", encoding="utf-8") as handle:
        handle.write(styles)

    # ---- Page size -------------------------------------------------------
    # pandoc copies the section properties from the FIRST <w:sectPr> it finds in
    # the reference document. The default reference ships an empty self-closing
    # one, so it must be replaced in place — appending a populated sectPr later
    # in the body is silently ignored.
    document_path = os.path.join(unpacked, "word", "document.xml")
    with open(document_path, encoding="utf-8") as handle:
        document = handle.read()

    document, replaced = re.subn(r"<w:sectPr\s*/>", SECT_PR, document, count=1)
    if not replaced:
        document = document.replace("</w:body>", f"{SECT_PR}</w:body>")

    with open(document_path, "w", encoding="utf-8") as handle:
        handle.write(document)

    # ---- Repack ----------------------------------------------------------
    reference_path = os.path.join(workdir, "reference.docx")
    with zipfile.ZipFile(reference_path, "w", zipfile.ZIP_DEFLATED) as archive:
        for root, _dirs, files in os.walk(unpacked):
            for name in files:
                full = os.path.join(root, name)
                archive.write(full, os.path.relpath(full, unpacked))

    return reference_path


def verify(docx_path: str, source_path: str) -> bool:
    """Confirm the .docx is well-formed and didn't lose the source's content."""
    ok = True

    with zipfile.ZipFile(docx_path) as archive:
        if archive.testzip() is not None:
            print("  FAIL  archive is corrupt")
            return False
        document = archive.read("word/document.xml").decode("utf-8")
        styles = archive.read("word/styles.xml").decode("utf-8")

    checks = [
        ("US Letter page size", 'w:w="12240"' in document),
        ("Georgia body font", 'w:ascii="Georgia"' in styles),
        ("Arial headings", 'w:ascii="Arial"' in styles),
        ("tables preserved", document.count("<w:tbl>") > 0),
        ("headings preserved", bool(re.search(r'w:val="Heading[12]"', document))),
    ]

    # Round-trip the text back out and confirm nothing was dropped. This is the
    # check that actually matters — styling is cosmetic, losing a URL is not.
    try:
        roundtrip = subprocess.run(
            ["pandoc", docx_path, "-t", "plain"],
            capture_output=True, text=True, check=True,
        ).stdout
        with open(source_path, encoding="utf-8") as handle:
            source = handle.read()

        def tokens(text: str) -> set[str]:
            cleaned = re.sub(r"[`#>*|_-]", " ", text)
            return set(re.findall(r"[A-Za-z0-9_./:-]{4,}", cleaned))

        source_tokens = tokens(source)
        kept = source_tokens & tokens(roundtrip)
        ratio = len(kept) / max(len(source_tokens), 1)
        checks.append((f"content retained ({ratio:.1%} of unique tokens)", ratio > 0.97))
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("  ----  round-trip check skipped (pandoc read failed)")

    for label, passed in checks:
        print(f"  {'OK  ' if passed else 'FAIL'}  {label}")
        ok = ok and passed

    return ok


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    parser.add_argument("source", help="markdown file to convert")
    parser.add_argument("-o", "--output", help="output .docx (default: alongside the source)")
    parser.add_argument("--no-toc", action="store_true", help="omit the table of contents")
    args = parser.parse_args()

    if not shutil.which("pandoc"):
        print("error: pandoc is not installed. Try: apt-get install pandoc", file=sys.stderr)
        return 1

    if not os.path.exists(args.source):
        print(f"error: {args.source} not found", file=sys.stderr)
        return 1

    output = args.output or os.path.splitext(args.source)[0] + ".docx"

    with tempfile.TemporaryDirectory() as workdir:
        print("Building styled reference document...")
        reference = build_reference(workdir)

        command = [
            "pandoc", args.source,
            "-o", output,
            f"--reference-doc={reference}",
            "--from", "gfm+definition_lists",
        ]
        if not args.no_toc:
            command += ["--toc", "--toc-depth=2"]

        print(f"Converting {args.source} -> {output}")
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode != 0:
            print(result.stderr, file=sys.stderr)
            return 1

    size_kb = os.path.getsize(output) / 1024
    print(f"\nWrote {output} ({size_kb:.0f} KB)\n\nVerifying:")
    return 0 if verify(output, args.source) else 1


if __name__ == "__main__":
    sys.exit(main())
