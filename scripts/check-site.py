#!/usr/bin/env python3
"""Structural checks for the static site in site/.

This is the same verification the deploy relies on: every page must be
well-formed, every local link and fragment must resolve inside site/, and no
page may pull an external asset. It uses only the standard library so it runs
identically on a laptop and on a GitHub Actions runner.

    python3 scripts/check-site.py
"""

from __future__ import annotations

import sys
import xml.etree.ElementTree as ET
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / "site"

VOID = {
    "area",
    "base",
    "br",
    "col",
    "embed",
    "hr",
    "img",
    "input",
    "link",
    "meta",
    "param",
    "source",
    "track",
    "wbr",
}

# Tags whose end tag HTML allows authors to omit. An implicit close is not a
# defect worth failing a deploy over, so they never produce a mismatch error.
OPTIONAL_END = {
    "caption",
    "colgroup",
    "dd",
    "dt",
    "li",
    "optgroup",
    "option",
    "p",
    "rp",
    "rt",
    "tbody",
    "td",
    "tfoot",
    "th",
    "thead",
    "tr",
}


class PageParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.stack: list[tuple[str, int]] = []
        self.ids: dict[str, int] = {}
        self.links: list[tuple[str, str]] = []
        self.errors: list[str] = []
        self.title = ""
        self.metas: dict[str, str] = {}
        self.html_lang: str | None = None
        self._in_title = False

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = {name: value or "" for name, value in attrs}
        line = self.getpos()[0]

        if tag == "html":
            self.html_lang = values.get("lang", "")

        if "id" in values:
            ident = values["id"]
            if ident in self.ids:
                self.errors.append(
                    f"line {line}: duplicate id '{ident}' (first used on line {self.ids[ident]})"
                )
            else:
                self.ids[ident] = line

        for attribute in ("href", "src"):
            value = values.get(attribute, "").strip()
            if value:
                self.links.append((attribute, value))

        if tag == "title":
            self._in_title = True
        elif tag == "meta":
            name = values.get("name", "")
            if name:
                self.metas[name] = values.get("content", "")

        if tag not in VOID:
            self.stack.append((tag, line))

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self.handle_starttag(tag, attrs)
        if tag not in VOID:
            self.stack.pop()

    def handle_endtag(self, tag: str) -> None:
        line = self.getpos()[0]
        if tag == "title":
            self._in_title = False
        if tag in VOID:
            return
        if not any(open_tag == tag for open_tag, _ in self.stack):
            self.errors.append(f"line {line}: </{tag}> has no matching open tag")
            return
        while self.stack:
            open_tag, opened = self.stack.pop()
            if open_tag == tag:
                return
            if open_tag not in OPTIONAL_END:
                self.errors.append(
                    f"line {line}: </{tag}> closes <{open_tag}> opened on line {opened}"
                )

    def handle_data(self, data: str) -> None:
        if self._in_title:
            self.title += data


def parse_page(path: Path) -> PageParser:
    parser = PageParser()
    parser.feed(path.read_text(encoding="utf-8"))
    parser.close()
    if parser.stack:
        for tag, line in parser.stack:
            parser.errors.append(f"line {line}: <{tag}> is never closed")
    return parser


def check_css(path: Path) -> list[str]:
    errors: list[str] = []
    depth = 0
    quote: str | None = None
    index = 0
    text = path.read_text(encoding="utf-8")
    while index < len(text):
        char = text[index]
        pair = text[index : index + 2]
        if quote:
            if char == "\\":
                index += 2
                continue
            if char == quote:
                quote = None
            index += 1
            continue
        if pair == "/*":
            end = text.find("*/", index + 2)
            if end == -1:
                errors.append("unclosed comment")
                break
            index = end + 2
            continue
        if char in "\"'":
            quote = char
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth < 0:
                errors.append("closing brace without an opening brace")
                depth = 0
        index += 1
    if depth:
        errors.append(f"{depth} unclosed block(s)")
    if not text.strip():
        errors.append("file is empty")
    return errors


def check_svg(path: Path) -> list[str]:
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError as error:
        return [f"invalid XML: {error}"]
    if not root.tag.endswith("svg"):
        return [f"root element is <{root.tag}>, expected <svg>"]
    return []


def main() -> int:
    if not SITE.is_dir():
        print(f"ERROR: site directory not found at {SITE}", file=sys.stderr)
        return 1

    pages = sorted(SITE.rglob("*.html"))
    if not pages:
        print(f"ERROR: no HTML pages in {SITE}", file=sys.stderr)
        return 1

    failures = 0
    parsed: dict[Path, PageParser] = {}

    for page in pages:
        parser = parse_page(page)
        parsed[page] = parser
        relative = page.relative_to(SITE)
        errors = list(parser.errors)

        if not parser.title.strip():
            errors.append("missing or empty <title>")
        if not parser.metas.get("description", "").strip():
            errors.append("missing meta description")
        if not parser.metas.get("viewport", "").strip():
            errors.append("missing viewport meta tag")
        if not parser.html_lang:
            errors.append("<html> is missing a lang attribute")

        for attribute, url in parser.links:
            parts = urlsplit(url)
            if parts.scheme in {"http", "https"}:
                if attribute == "src":
                    errors.append(f"external asset must not be required: {url}")
                continue
            if parts.scheme in {"mailto", "tel"}:
                continue
            if parts.scheme or url.startswith("//"):
                errors.append(f"unsupported URL scheme: {url}")
                continue

            if parts.path:
                target = (page.parent / unquote(parts.path)).resolve()
            else:
                target = page.resolve()

            if SITE.resolve() not in target.parents and target != SITE.resolve():
                errors.append(f"link escapes site/: {url}")
                continue
            if not target.exists():
                errors.append(f"broken local {attribute}: {url}")
                continue
            if parts.fragment:
                target_parser = parsed.get(target)
                if target_parser is None and target.suffix == ".html":
                    target_parser = parse_page(target)
                    parsed[target] = target_parser
                if target_parser is not None and parts.fragment not in target_parser.ids:
                    errors.append(f"undefined fragment #{parts.fragment} in {url}")

        if errors:
            failures += 1
            print(f"FAIL {relative}")
            for error in errors:
                print(f"  - {error}")
        else:
            print(
                f"ok   {relative} "
                f"({len(parser.ids)} ids, {len(parser.links)} links)"
            )

    for stylesheet in sorted(SITE.rglob("*.css")):
        errors = check_css(stylesheet)
        relative = stylesheet.relative_to(SITE)
        if errors:
            failures += 1
            print(f"FAIL {relative}")
            for error in errors:
                print(f"  - {error}")
        else:
            print(f"ok   {relative}")

    for asset in sorted(SITE.rglob("*.svg")):
        errors = check_svg(asset)
        relative = asset.relative_to(SITE)
        if errors:
            failures += 1
            print(f"FAIL {relative}")
            for error in errors:
                print(f"  - {error}")
        else:
            print(f"ok   {relative}")

    if failures:
        print(f"\n{failures} file(s) failed site checks", file=sys.stderr)
        return 1

    print(f"\nsite is consistent: {len(pages)} page(s) checked")
    return 0


if __name__ == "__main__":
    sys.exit(main())
