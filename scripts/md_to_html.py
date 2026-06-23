#!/usr/bin/env python3
"""Convert a Markdown file to a self-contained, styled HTML document.

This is the zero-dependency floor of the teach-me render toolkit: it imports
only the Python standard library, so it ALWAYS works — no pandoc, no pip, no
network. The render ladder uses it as the last-resort HTML engine, but it is
also fine to call directly.

Supported Markdown:
  - ATX headings (# .. ######)
  - paragraphs
  - **bold**, *italic* / _italic_, `inline code`
  - [links](http://example.com)
  - fenced code blocks (``` or ~~~), with the language label preserved as a class
  - unordered lists (-, *, +) and ordered lists (1.), single level of nesting
  - blockquotes (>)
  - horizontal rules (---, ***, ___)
  - simple GitHub-style pipe tables (with a | --- | separator row)

Anything fancier degrades gracefully to escaped text. The goal is a faithful,
readable, print-friendly document — not a spec-complete CommonMark parser.

If the third-party `markdown` library happens to be importable it is used for
the body (richer parsing); otherwise the bundled stdlib parser handles it. Pass
--builtin to force the stdlib path (used to prove the zero-dependency floor).
Either way the output is wrapped in the same self-contained styled template.

Usage: md_to_html.py <path/to/file.md> [-o <out.html>] [--title "Title"] [--builtin]

Exit codes:
  0  success — wrote <file>.html (or the -o target)
  64 usage error
  2  input file not found
"""

from __future__ import annotations

import argparse
import html
import re
import sys
from pathlib import Path

# --- inline-level rendering -------------------------------------------------

_CODE_SPAN = re.compile(r"`([^`]+)`")
_BOLD = re.compile(r"\*\*(.+?)\*\*")
_ITALIC = re.compile(r"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)|_(.+?)_")
_LINK = re.compile(r"\[([^\]]+)\]\((\S+?)\)")


def render_inline(text: str) -> str:
    """Escape, then apply inline Markdown. Code spans are protected first."""
    placeholders: list[str] = []

    def _stash_code(m: re.Match) -> str:
        placeholders.append(html.escape(m.group(1)))
        return f"\x00{len(placeholders) - 1}\x00"

    text = _CODE_SPAN.sub(_stash_code, text)
    text = html.escape(text, quote=False)

    text = _LINK.sub(
        lambda m: f'<a href="{html.escape(m.group(2), quote=True)}">{m.group(1)}</a>',
        text,
    )
    text = _BOLD.sub(r"<strong>\1</strong>", text)
    text = _ITALIC.sub(
        lambda m: f"<em>{m.group(1) if m.group(1) is not None else m.group(2)}</em>",
        text,
    )

    def _restore_code(m: re.Match) -> str:
        return f"<code>{placeholders[int(m.group(1))]}</code>"

    text = re.sub(r"\x00(\d+)\x00", _restore_code, text)
    return text


# --- block-level rendering --------------------------------------------------

_HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")
_FENCE = re.compile(r"^(```|~~~)\s*([\w+-]*)\s*$")
_HR = re.compile(r"^\s*([-*_])(\s*\1){2,}\s*$")
_ULI = re.compile(r"^\s*[-*+]\s+(.*)$")
_OLI = re.compile(r"^\s*\d+\.\s+(.*)$")
_QUOTE = re.compile(r"^\s*>\s?(.*)$")
_TABLE_SEP = re.compile(r"^\s*\|?\s*:?-{1,}:?\s*(\|\s*:?-{1,}:?\s*)+\|?\s*$")


def _split_row(line: str) -> list[str]:
    line = line.strip()
    if line.startswith("|"):
        line = line[1:]
    if line.endswith("|"):
        line = line[:-1]
    return [c.strip() for c in line.split("|")]


def render_blocks(md: str) -> str:
    lines = md.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    out: list[str] = []
    i = 0
    n = len(lines)

    while i < n:
        line = lines[i]

        # fenced code block
        fence = _FENCE.match(line)
        if fence:
            marker, lang = fence.group(1), fence.group(2)
            i += 1
            buf: list[str] = []
            while i < n and lines[i].strip() != marker:
                buf.append(lines[i])
                i += 1
            i += 1  # consume closing fence (if present)
            cls = f' class="language-{html.escape(lang, quote=True)}"' if lang else ""
            code = html.escape("\n".join(buf))
            out.append(f"<pre><code{cls}>{code}</code></pre>")
            continue

        # blank line
        if not line.strip():
            i += 1
            continue

        # horizontal rule
        if _HR.match(line):
            out.append("<hr>")
            i += 1
            continue

        # heading
        h = _HEADING.match(line)
        if h:
            level = len(h.group(1))
            out.append(f"<h{level}>{render_inline(h.group(2))}</h{level}>")
            i += 1
            continue

        # table: header row + separator row
        if "|" in line and i + 1 < n and _TABLE_SEP.match(lines[i + 1]):
            header = _split_row(line)
            i += 2
            rows: list[list[str]] = []
            while i < n and "|" in lines[i] and lines[i].strip():
                rows.append(_split_row(lines[i]))
                i += 1
            thead = "".join(f"<th>{render_inline(c)}</th>" for c in header)
            body = "".join(
                "<tr>" + "".join(f"<td>{render_inline(c)}</td>" for c in r) + "</tr>"
                for r in rows
            )
            out.append(
                f"<table><thead><tr>{thead}</tr></thead><tbody>{body}</tbody></table>"
            )
            continue

        # blockquote
        if _QUOTE.match(line):
            buf = []
            while i < n and _QUOTE.match(lines[i]):
                buf.append(_QUOTE.match(lines[i]).group(1))
                i += 1
            out.append(f"<blockquote>{render_blocks(chr(10).join(buf))}</blockquote>")
            continue

        # lists (unordered / ordered)
        if _ULI.match(line) or _OLI.match(line):
            ordered = bool(_OLI.match(line))
            item_re = _OLI if ordered else _ULI
            items: list[str] = []
            while i < n and item_re.match(lines[i]):
                items.append(render_inline(item_re.match(lines[i]).group(1)))
                i += 1
            tag = "ol" if ordered else "ul"
            lis = "".join(f"<li>{it}</li>" for it in items)
            out.append(f"<{tag}>{lis}</{tag}>")
            continue

        # paragraph: gather consecutive non-blank, non-special lines
        buf = [line]
        i += 1
        while i < n and lines[i].strip() and not (
            _HEADING.match(lines[i])
            or _FENCE.match(lines[i])
            or _HR.match(lines[i])
            or _ULI.match(lines[i])
            or _OLI.match(lines[i])
            or _QUOTE.match(lines[i])
        ):
            buf.append(lines[i])
            i += 1
        paragraph = render_inline(" ".join(s.strip() for s in buf))
        out.append(f"<p>{paragraph}</p>")

    return "\n".join(out)


# --- document template ------------------------------------------------------

_CSS = """
:root { color-scheme: light; }
* { box-sizing: border-box; }
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  line-height: 1.65; color: #1a1a1a; background: #fff;
  max-width: 46rem; margin: 0 auto; padding: 3rem 1.5rem;
}
h1, h2, h3, h4, h5, h6 { line-height: 1.25; margin: 2rem 0 0.75rem; font-weight: 650; }
h1 { font-size: 2rem; border-bottom: 2px solid #eee; padding-bottom: .4rem; }
h2 { font-size: 1.5rem; border-bottom: 1px solid #eee; padding-bottom: .3rem; }
h3 { font-size: 1.2rem; }
p { margin: 0.85rem 0; }
a { color: #0b5fff; text-decoration: none; }
a:hover { text-decoration: underline; }
code {
  font-family: "SF Mono", SFMono-Regular, Consolas, "Liberation Mono", Menlo, monospace;
  font-size: 0.9em; background: #f3f3f5; padding: 0.15em 0.4em; border-radius: 4px;
}
pre {
  background: #1e1e2e; color: #e4e4ef; padding: 1rem 1.25rem; border-radius: 8px;
  overflow-x: auto; line-height: 1.5;
}
pre code { background: none; padding: 0; color: inherit; font-size: 0.85rem; }
blockquote {
  margin: 1rem 0; padding: 0.25rem 1.25rem; border-left: 4px solid #d0d0d8;
  color: #555; background: #fafafa;
}
ul, ol { margin: 0.85rem 0; padding-left: 1.6rem; }
li { margin: 0.3rem 0; }
hr { border: none; border-top: 1px solid #e2e2e8; margin: 2rem 0; }
table { border-collapse: collapse; width: 100%; margin: 1.25rem 0; font-size: 0.95rem; }
th, td { border: 1px solid #e2e2e8; padding: 0.5rem 0.75rem; text-align: left; }
th { background: #f6f6f8; font-weight: 650; }
tbody tr:nth-child(even) { background: #fafafa; }
@media print {
  body { max-width: none; padding: 0; }
  pre { white-space: pre-wrap; word-wrap: break-word; }
  a { color: inherit; }
}
""".strip()


def render_body(md: str, force_builtin: bool = False) -> str:
    """Render Markdown body to HTML, preferring the `markdown` lib when present."""
    if not force_builtin:
        try:
            import markdown  # type: ignore

            return markdown.markdown(
                md, extensions=["fenced_code", "tables", "sane_lists"]
            )
        except Exception:
            pass  # fall through to the stdlib parser
    return render_blocks(md)


def build_document(title: str, body: str) -> str:
    return (
        "<!DOCTYPE html>\n"
        '<html lang="en">\n<head>\n<meta charset="utf-8">\n'
        '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
        f"<title>{html.escape(title)}</title>\n"
        f"<style>\n{_CSS}\n</style>\n</head>\n<body>\n{body}\n</body>\n</html>\n"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="path to the Markdown file")
    parser.add_argument("-o", "--output", type=Path, help="output .html path")
    parser.add_argument("--title", help="document title (default: derived from filename)")
    parser.add_argument(
        "--builtin",
        action="store_true",
        help="force the stdlib parser even if the markdown library is installed",
    )
    args = parser.parse_args()

    if not args.input.is_file():
        print(f"error: file not found: {args.input}", file=sys.stderr)
        return 2

    md = args.input.read_text(encoding="utf-8")
    title = args.title or args.input.stem.replace("-", " ").replace("_", " ").strip()
    output = args.output or args.input.with_suffix(".html")

    body = render_body(md, force_builtin=args.builtin)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(build_document(title, body), encoding="utf-8")
    print(f"wrote {output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
