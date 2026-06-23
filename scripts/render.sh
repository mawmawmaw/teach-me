#!/usr/bin/env bash
# Render a Markdown file to HTML or PDF, degrading gracefully so that output
# (almost) never hard-fails.
#
# Usage: render.sh <path/to/file.md> <html|pdf>
#
# Optional environment:
#   RENDER_ENGINE   an engine id from probe_render.sh (e.g. "pandoc+xelatex",
#                   "weasyprint", "builtin", "html-print"). When unset, render.sh
#                   probes for the best available engine itself.
#
# Render ladders (each degrades downward):
#
#   PDF: pandoc+<engine>  ->  HTML->PDF (weasyprint / wkhtmltopdf)  ->  typst
#        ->  fall back to HTML (always works); user prints to PDF from a browser
#
#   HTML: pandoc standalone  ->  md_to_html.py (markdown lib if present, else
#         stdlib floor — always works)
#
# On success it writes the artifact next to the .md and prints a one-line
# summary of the format+engine actually used on stdout, e.g.
#   wrote lesson.pdf via pandoc+xelatex
#   wrote lesson.html via builtin (pdf engine unavailable — print to PDF from a browser)
#
# Bottom rung: if there is NO pandoc and NO Python 3 interpreter, no scripted
# renderer can run. render.sh then exits 5 and prints "needs-agent-html" — the
# calling agent must author the self-contained HTML document itself (Claude can
# emit styled HTML with no interpreter). This keeps "output never hard-fails"
# true even on a machine with neither pandoc nor Python.
#
# Exit codes:
#   0   an artifact was written (possibly a fallback format — read stdout)
#   4   a scripted renderer was available but failed (effectively never)
#   5   no scripted renderer available (no pandoc, no Python) — agent authors HTML
#   64  usage error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <path-to-file.md> <html|pdf>" >&2
  exit 64
fi

SRC="$1"
FORMAT="$2"

if [[ ! -f "$SRC" ]]; then
  echo "error: file not found: $SRC" >&2
  exit 64
fi
if [[ "$FORMAT" != "html" && "$FORMAT" != "pdf" ]]; then
  echo "error: format must be 'html' or 'pdf' (got '$FORMAT')" >&2
  exit 64
fi

BASE="${SRC%.md}"
TITLE="$(basename "$BASE" | tr -- '-_' '  ')"
HTML_OUT="${BASE}.html"
PDF_OUT="${BASE}.pdf"

have() { command -v "$1" >/dev/null 2>&1; }

# Resolve a usable Python 3 interpreter (python3, then python>=3). Empty if none.
PYTHON_BIN=""
for c in python3 python; do
  if have "$c" && "$c" -c 'import sys; raise SystemExit(0 if sys.version_info[0] >= 3 else 1)' >/dev/null 2>&1; then
    PYTHON_BIN="$c"; break
  fi
done
have_module() { [[ -n "$PYTHON_BIN" ]] && "$PYTHON_BIN" -c "import $1" >/dev/null 2>&1; }
# HTML is scriptable when either pandoc or a Python interpreter is present.
html_scriptable() { have pandoc || [[ -n "$PYTHON_BIN" ]]; }

# Resolve the engine hint. If absent or stale, probe for the right one.
ENGINE="${RENDER_ENGINE:-}"
probe_engine() {
  local kind="$1" # html | pdf
  "$SCRIPT_DIR/probe_render.sh" 2>/dev/null | sed -n "s/^${kind}_engine=//p"
}

# --- HTML rendering (always succeeds via the stdlib floor) ------------------
render_html() {
  # 1. pandoc standalone (best fidelity)
  if have pandoc; then
    if pandoc "$SRC" -o "$HTML_OUT" --standalone --metadata title="$TITLE" 2>/dev/null; then
      echo "pandoc"
      return 0
    fi
  fi
  # 2./3. markdown lib if importable, else stdlib floor — both via md_to_html.py.
  if [[ -n "$PYTHON_BIN" ]]; then
    if "$PYTHON_BIN" "$SCRIPT_DIR/md_to_html.py" "$SRC" -o "$HTML_OUT" --title "$TITLE" >/dev/null 2>&1; then
      if have_module markdown; then echo "python-markdown"; else echo "builtin"; fi
      return 0
    fi
    # Last resort: force the stdlib path explicitly.
    if "$PYTHON_BIN" "$SCRIPT_DIR/md_to_html.py" "$SRC" -o "$HTML_OUT" --title "$TITLE" --builtin >/dev/null 2>&1; then
      echo "builtin"
      return 0
    fi
  fi
  return 1
}

# --- PDF rendering ----------------------------------------------------------
pandoc_pdf() {
  local engine="$1" # weasyprint | xelatex | tectonic | typst | pdflatex | wkhtmltopdf
  pandoc "$SRC" -o "$PDF_OUT" \
    --pdf-engine="$engine" --standalone --metadata title="$TITLE" 2>/dev/null
}

html_to_pdf() {
  # Produce HTML first, then convert HTML->PDF with the given tool.
  local tool="$1" # weasyprint | wkhtmltopdf
  render_html >/dev/null || return 1
  case "$tool" in
    weasyprint)
      if have weasyprint; then weasyprint "$HTML_OUT" "$PDF_OUT" 2>/dev/null
      else python3 -m weasyprint "$HTML_OUT" "$PDF_OUT" 2>/dev/null; fi ;;
    wkhtmltopdf) wkhtmltopdf "$HTML_OUT" "$PDF_OUT" 2>/dev/null ;;
    *) return 1 ;;
  esac
}

render_pdf() {
  # Returns the engine id used on stdout, or non-zero if no PDF path worked.
  local hint="${ENGINE:-}"
  [[ -z "$hint" || "$hint" == "html-print" ]] && hint="$(probe_engine pdf || true)"

  case "$hint" in
    pandoc+*)
      local eng="${hint#pandoc+}"
      if have pandoc && pandoc_pdf "$eng"; then echo "$hint"; return 0; fi
      ;;
    weasyprint)
      if { have weasyprint || have_module weasyprint; } && html_to_pdf weasyprint; then
        echo "weasyprint"; return 0
      fi
      ;;
    wkhtmltopdf)
      if have wkhtmltopdf && html_to_pdf wkhtmltopdf; then echo "wkhtmltopdf"; return 0; fi
      ;;
    typst)
      if have typst && have pandoc && pandoc_pdf typst; then echo "pandoc+typst"; return 0; fi
      ;;
  esac

  # Generic best-effort ladder, independent of the hint, in preference order.
  if have pandoc; then
    for eng in weasyprint xelatex tectonic typst pdflatex wkhtmltopdf; do
      if have "$eng"; then
        if pandoc_pdf "$eng"; then echo "pandoc+$eng"; return 0; fi
      fi
    done
  fi
  if { have weasyprint || have_module weasyprint; } && html_to_pdf weasyprint; then
    echo "weasyprint"; return 0
  fi
  if have wkhtmltopdf && html_to_pdf wkhtmltopdf; then echo "wkhtmltopdf"; return 0; fi

  return 1 # no PDF engine — caller falls back to HTML
}

# --- dispatch ---------------------------------------------------------------
# Bottom rung: nothing scriptable (no pandoc, no Python) — the agent must
# author the HTML document directly. Signal that with exit 5.
if ! html_scriptable; then
  echo "needs-agent-html (no pandoc and no Python 3 — author the HTML document directly)"
  exit 5
fi

if [[ "$FORMAT" == "html" ]]; then
  if used="$(render_html)"; then
    echo "wrote $HTML_OUT via $used"
    exit 0
  fi
  echo "error: failed to render HTML for $SRC" >&2
  exit 4
fi

# FORMAT == pdf
if used="$(render_pdf)"; then
  echo "wrote $PDF_OUT via $used"
  exit 0
fi

# No PDF engine available — fall back to HTML (always works while scriptable).
if used="$(render_html)"; then
  echo "wrote $HTML_OUT via $used (pdf engine unavailable — print to PDF from a browser)"
  exit 0
fi

echo "error: failed to render any artifact for $SRC" >&2
exit 4
