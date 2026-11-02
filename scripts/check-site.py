#!/usr/bin/env python3
"""Structural checks for the static site in site/.

This is the same verification the deploy relies on: every page must be
well-formed, every local link and fragment must resolve inside site/, and no
page may pull an external asset. It uses only the standard library so it runs
identically on a laptop and on a GitHub Actions runner.

    python3 scripts/check-site.py
"""

from __future__ import annotations

import json
import re
import struct
import sys
import xml.etree.ElementTree as ET
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / "site"

# The one host the pages advertise themselves as. Every absolute URL in the metadata has to use it,
# or a link preview points at a different site than the one a person lands on.
SITE_HOST = "oreja-tau.vercel.app"
SITE_URL = f"https://{SITE_HOST}"
SITEMAP_URL = f"{SITE_URL}/sitemap.xml"

# What a crawler needs before a link to this page is worth anything. Missing any of these does not
# break the page for a reader, which is exactly why it needs a machine to notice.
REQUIRED_META = [
    "og:type",
    "og:site_name",
    "og:url",
    "og:title",
    "og:description",
    "og:image",
    "og:image:width",
    "og:image:height",
    "og:image:alt",
    "twitter:card",
    "twitter:title",
    "twitter:description",
    "twitter:image",
]

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
        self.canonical: list[str] = []
        self.jsonld: list[str] = []
        self.h1 = 0
        self.summaries: list[str] = []
        self.html_lang: str | None = None
        self._in_title = False
        self._in_jsonld = False
        self._in_summary = False
        self._summary = ""

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
        elif tag == "h1":
            self.h1 += 1
        elif tag == "summary":
            self._in_summary = True
            self._summary = ""
        elif tag == "meta":
            # Open Graph uses property=, Twitter and the rest use name=; both live in one map so a
            # caller never has to know which.
            key = values.get("property") or values.get("name", "")
            if key:
                self.metas[key] = values.get("content", "")
        elif tag == "link" and "canonical" in values.get("rel", "").split():
            self.canonical.append(values.get("href", ""))
        elif tag == "script" and values.get("type", "").lower() == "application/ld+json":
            self._in_jsonld = True

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
        if tag == "summary":
            self._in_summary = False
            self.summaries.append(normalize(self._summary))
        if tag == "script":
            self._in_jsonld = False
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
        elif self._in_summary:
            self._summary += data
        elif self._in_jsonld:
            self.jsonld.append(data)


def normalize(text: str) -> str:
    """One-space text, so a comparison is about words and not about line wrapping."""
    return " ".join(text.split())


def parse_page(path: Path) -> PageParser:
    parser = PageParser()
    parser.feed(path.read_text(encoding="utf-8"))
    parser.close()
    if parser.stack:
        for tag, line in parser.stack:
            parser.errors.append(f"line {line}: <{tag}> is never closed")
    return parser


def url_for(path: Path) -> str:
    """The canonical URL of a page in site/."""
    relative = path.relative_to(SITE).as_posix()
    return SITE_URL + "/" if relative == "index.html" else f"{SITE_URL}/{relative}"


def local_path(url: str) -> Path | None:
    """Map an absolute URL on our own host back to a file in site/, or None if it is elsewhere."""
    parts = urlsplit(url)
    if parts.scheme != "https" or parts.netloc != SITE_HOST:
        return None
    name = unquote(parts.path).lstrip("/") or "index.html"
    if name.endswith("/"):
        name += "index.html"
    return SITE / name


def png_size(path: Path) -> tuple[int, int] | None:
    """Width and height from a PNG's IHDR, without decoding it."""
    data = path.read_bytes()[:24]
    if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        return None
    return struct.unpack(">II", data[16:24])


def check_seo(page: Path, parser: PageParser) -> list[str]:
    """The link-preview and indexing contract: stable URLs, one card, one valid entity."""
    errors: list[str] = []
    metas = parser.metas
    expected = url_for(page)

    if not parser.canonical:
        errors.append("missing <link rel=\"canonical\">")
    elif len(parser.canonical) > 1:
        errors.append(f"{len(parser.canonical)} canonical links; there must be exactly one")
    elif parser.canonical[0] != expected:
        errors.append(f"canonical is {parser.canonical[0]!r}, expected {expected!r}")

    for name in REQUIRED_META:
        if not metas.get(name, "").strip():
            errors.append(f"missing meta {name}")

    if metas.get("og:url", "").strip() and metas["og:url"] != expected:
        errors.append(f"og:url is {metas['og:url']!r}, expected {expected!r}")

    # A relative og:image is read from the crawler's own host by some services and silently fails
    # in others, so every preview URL has to be absolute and served from this site.
    for name in ("og:image", "twitter:image"):
        value = metas.get(name, "").strip()
        if not value:
            continue
        target = local_path(value)
        if target is None:
            errors.append(f"{name} must be absolute on https://{SITE_HOST}: {value}")
            continue
        if not target.is_file():
            errors.append(f"{name} points at a missing file: {value}")

    image = local_path(metas.get("og:image", ""))
    if image is not None and image.is_file():
        size = png_size(image)
        if size is None:
            errors.append(f"og:image is not a PNG: {metas['og:image']}")
        else:
            declared = (
                metas.get("og:image:width", "").strip(),
                metas.get("og:image:height", "").strip(),
            )
            if declared != (str(size[0]), str(size[1])):
                errors.append(
                    f"og:image is {size[0]}x{size[1]} but the tags declare "
                    f"{declared[0] or '?'}x{declared[1] or '?'}"
                )

    if "noindex" in metas.get("robots", "").lower():
        errors.append("robots says noindex on a page that should be indexed")

    # A page without a language is guessed at by the crawler, and a long title is cut off in the
    # result line, so both are limits rather than opinions.
    if not (parser.html_lang or "").strip():
        errors.append("missing lang on <html>")
    title = normalize(parser.title)
    if not 15 <= len(title) <= 65:
        errors.append(f"title is {len(title)} characters, expected 15-65: {title!r}")
    description = normalize(metas.get("description", ""))
    if not 50 <= len(description) <= 165:
        errors.append(f"meta description is {len(description)} characters, expected 50-165")
    if parser.h1 != 1:
        errors.append(f"page has {parser.h1} <h1> elements; it must have exactly one")

    card = metas.get("twitter:card", "").strip()
    if card and card != "summary_large_image":
        errors.append(f"twitter:card is {card!r}; the 1200x630 card needs summary_large_image")

    if not parser.jsonld:
        errors.append("no application/ld+json structured data")
    for block in parser.jsonld:
        try:
            data = json.loads(block)
        except json.JSONDecodeError as error:
            errors.append(f"structured data is not valid JSON: {error}")
            continue
        if data.get("@context") != "https://schema.org":
            errors.append("structured data has no schema.org @context")
        # A single node and a @graph are both legal; a graph is what lets two entities point at
        # each other, so the reference check below only has something to do in that form.
        nodes = data.get("@graph", [data])
        if not isinstance(nodes, list) or not nodes:
            errors.append("structured data has no nodes")
            continue
        for node in nodes:
            if not isinstance(node, dict) or not node.get("@type"):
                errors.append("structured data node has no @type")
                continue
            if node["@type"] == "FAQPage":
                errors.extend(check_faq(node, parser))
            # An @id that nothing defines is how a graph silently splits in two: the reference
            # resolves to a blank node and the publisher is lost.
            ids = {entry.get("@id") for entry in nodes if isinstance(entry, dict) and entry.get("@id")}
            for key, value in _references(node):
                if value not in ids:
                    errors.append(f"{node['@type']}.{key} points at an undefined @id: {value}")

    return errors


def _references(node: dict) -> list[tuple[str, str]]:
    """Every {\"@id\": ...} reference inside a node, as (location, id)."""
    found: list[tuple[str, str]] = []
    for key, value in node.items():
        if key == "@id":
            continue
        if isinstance(value, dict) and set(value) == {"@id"}:
            found.append((key, value["@id"]))
    return found


def check_faq(node: dict, parser: PageParser) -> list[str]:
    """The FAQ markup has to answer the questions the page actually asks."""
    errors: list[str] = []
    questions = []
    for item in node.get("mainEntity", []):
        if not isinstance(item, dict) or item.get("@type") != "Question":
            errors.append("FAQPage mainEntity entry is not a Question")
            continue
        questions.append(normalize(item.get("name", "")))
        answer = item.get("acceptedAnswer")
        if not isinstance(answer, dict) or not normalize(answer.get("text", "")):
            errors.append(f"FAQ question has no answer text: {item.get('name')!r}")
    visible = parser.summaries
    if not visible:
        errors.append("FAQPage is declared but the page shows no <summary> questions")
        return errors
    for question in questions:
        if question not in visible:
            errors.append(f"FAQ question is not on the page: {question!r}")
    for summary in visible:
        if summary not in questions:
            errors.append(f"page question is missing from FAQPage: {summary!r}")

    return errors


def check_sitemap(pages: list[Path], parsed: dict[Path, PageParser]) -> list[str]:
    """Every page in the sitemap has to exist, and every page that exists has to be in it."""
    errors: list[str] = []
    path = SITE / "sitemap.xml"
    if not path.is_file():
        return ["missing sitemap.xml"]
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError as error:
        return [f"sitemap.xml is not valid XML: {error}"]

    listed = [element.text.strip() for element in root.iter("{http://www.sitemaps.org/schemas/sitemap/0.9}loc") if element.text]
    for url in listed:
        target = local_path(url)
        if target is None:
            errors.append(f"sitemap URL is not on https://{SITE_HOST}: {url}")
        elif not target.is_file():
            errors.append(f"sitemap lists a missing page: {url}")

    for page in pages:
        url = url_for(page)
        if url not in listed:
            errors.append(f"{page.relative_to(SITE)} is not in sitemap.xml")
            continue
        parser = parsed[page]
        if parser.canonical and parser.canonical[0] != url:
            errors.append(
                f"{page.relative_to(SITE)} canonical and sitemap disagree "
                f"({parser.canonical[0]} vs {url})"
            )
    return errors


def check_robots() -> list[str]:
    path = SITE / "robots.txt"
    if not path.is_file():
        return ["missing robots.txt"]
    text = path.read_text(encoding="utf-8")
    if SITEMAP_URL not in text:
        return [f"robots.txt does not point at {SITEMAP_URL}"]
    if "Disallow: /" in text:
        return ["robots.txt disallows the whole site"]
    return []


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


def check_js(path: Path, defined: set[str]) -> list[str]:
    """A page script may only reach for globals another page script defines.

    Renaming a script's global without renaming its caller leaves the page silently
    inert: the file loads, nothing throws, and no scroll act ever mounts. That is a
    deploy-time failure the browser cannot report, so it is checked here."""
    text = path.read_text(encoding="utf-8")
    missing = [
        name
        for name in sorted(set(re.findall(r"window\.([A-Z]\w*)", text)))
        if name not in defined
    ]
    return [f"window.{name} is used but no site script defines it" for name in missing]


def site_globals() -> set[str]:
    defined: set[str] = set()
    for script in SITE.rglob("*.js"):
        text = script.read_text(encoding="utf-8")
        defined.update(re.findall(r"(?:window|global)\.([A-Z]\w*)\s*=", text))
    return defined


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
        errors.extend(check_seo(page, parser))

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

    defined_globals = site_globals()
    for script in sorted(SITE.rglob("*.js")):
        errors = check_js(script, defined_globals)
        relative = script.relative_to(SITE)
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

    for label, errors in (
        ("sitemap.xml", check_sitemap(pages, parsed)),
        ("robots.txt", check_robots()),
    ):
        if errors:
            failures += 1
            print(f"FAIL {label}")
            for error in errors:
                print(f"  - {error}")
        else:
            print(f"ok   {label}")

    if failures:
        print(f"\n{failures} file(s) failed site checks", file=sys.stderr)
        return 1

    print(f"\nsite is consistent: {len(pages)} page(s) checked")
    return 0


if __name__ == "__main__":
    sys.exit(main())
