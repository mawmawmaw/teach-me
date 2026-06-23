#!/usr/bin/env python3
"""Initialize a teach-me progress.json from a course outline.md.

Parses `## Module Title` (module) and `### Lesson Title` (lesson) headings
from the outline and emits a skeleton progress.json with every lesson set
to status="not_started".
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

HEADING_RE = re.compile(r"^(#{2,3})\s+(.+?)\s*$")


def slugify(text: str) -> str:
    text = text.strip().lower()
    text = re.sub(r"[^\w\s-]", "", text)
    text = re.sub(r"[\s_]+", "-", text)
    return text.strip("-") or "untitled"


def parse_outline(outline_path: Path) -> list[dict]:
    modules: list[dict] = []
    current_module: dict | None = None
    module_idx = 0
    lesson_idx = 0

    for raw_line in outline_path.read_text(encoding="utf-8").splitlines():
        m = HEADING_RE.match(raw_line)
        if not m:
            continue
        level = len(m.group(1))
        title = m.group(2).strip()
        if level == 2:
            module_idx += 1
            lesson_idx = 0
            current_module = {
                "id": f"{module_idx:02d}-{slugify(title)}",
                "title": title,
                "lessons": [],
            }
            modules.append(current_module)
        elif level == 3:
            if current_module is None:
                # lessons before any module — wrap in a default one
                module_idx += 1
                current_module = {
                    "id": f"{module_idx:02d}-introduction",
                    "title": "Introduction",
                    "lessons": [],
                }
                modules.append(current_module)
            lesson_idx += 1
            current_module["lessons"].append(
                {
                    "id": f"{lesson_idx:02d}-{slugify(title)}",
                    "title": title,
                    "status": "not_started",
                    "evaluation": None,
                }
            )
    return modules


def first_lesson_path(modules: list[dict]) -> str | None:
    for module in modules:
        if module["lessons"]:
            return f"{module['id']}/{module['lessons'][0]['id']}"
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--slug", required=True)
    parser.add_argument("--topic", required=True)
    parser.add_argument("--language", required=True)
    parser.add_argument(
        "--level",
        required=True,
        choices=["beginner", "intermediate", "advanced"],
    )
    parser.add_argument(
        "--formats",
        required=True,
        help="comma-separated output formats beyond markdown, e.g. 'html,pdf' "
        "(use 'markdown' or '' for markdown-only)",
    )
    parser.add_argument("--outline", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()

    if not args.outline.is_file():
        print(f"error: outline not found: {args.outline}", file=sys.stderr)
        return 2

    if args.output.exists() and not args.force:
        print(
            f"error: {args.output} already exists (use --force to overwrite)",
            file=sys.stderr,
        )
        return 3

    modules = parse_outline(args.outline)
    if not modules:
        print(
            f"error: no '## Module' / '### Lesson' headings found in {args.outline}",
            file=sys.stderr,
        )
        return 4

    # Normalize formats: markdown is always present; html/pdf are opt-in.
    requested = {f.strip().lower() for f in args.formats.split(",") if f.strip()}
    output_formats = ["markdown"]
    for fmt in ("html", "pdf"):
        if fmt in requested:
            output_formats.append(fmt)

    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    payload = {
        "course": {
            "slug": args.slug,
            "topic": args.topic,
            "language": args.language,
            "baseline_level": args.level,
            "output_formats": output_formats,
            "html_engine": None,
            "pdf_engine": None,
            "created_at": now,
            "updated_at": now,
        },
        "baseline_assessment": None,
        "current_lesson": first_lesson_path(modules),
        "modules": modules,
        "final_assessment": None,
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
