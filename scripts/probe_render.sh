#!/usr/bin/env bash
# Probe the system for available Markdown -> HTML and Markdown -> PDF toolchains,
# plus the prerequisites those toolchains depend on (a Python 3 interpreter) and
# the OS (so install hints are correct for the platform).
#
# Usage: probe_render.sh
#
# Behavior:
#   - Does NOT install anything. The agent + user decide what to install.
#   - Reports capability on stdout as key=value lines:
#       os=macos|debian|fedora|arch|linux|windows|unknown
#       python=<interpreter name>|missing      # python3, then python (>=3); else missing
#       html_engine=<id>
#       pdf_engine=<id>
#   - Prints a human-readable found/missing summary and OS-correct install hints
#     on stderr.
#
# HTML engine identifiers (one is ALWAYS reported — output can never hard-fail):
#       pandoc            best fidelity, if pandoc is on PATH (needs no Python)
#       python-markdown   Python 3 present and the pip `markdown` module imports
#       builtin           Python 3 present; bundled stdlib-only md_to_html.py
#       agent             NO pandoc and NO Python — the agent must author the HTML
#                         document directly (Claude can emit self-contained HTML
#                         with no interpreter). This is the true bottom rung.
#
# PDF engine identifiers:
#       pandoc+weasyprint | pandoc+xelatex | pandoc+tectonic | pandoc+typst
#       pandoc+pdflatex   | pandoc+wkhtmltopdf
#       weasyprint        standalone HTML->PDF (fed by the HTML ladder)
#       wkhtmltopdf       standalone HTML->PDF (fed by the HTML ladder)
#       typst             standalone (md -> typst -> pdf via render.sh)
#       html-print        no PDF engine, but HTML is available; user prints to PDF
#
# Exit codes:
#   0  probe completed (always, unless usage error)
#  64  usage error

set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo "usage: $0" >&2
  exit 64
fi

have() { command -v "$1" >/dev/null 2>&1; }

# --- Python 3 interpreter ---------------------------------------------------
PYTHON_BIN=""
for c in python3 python; do
  if have "$c" && "$c" -c 'import sys; raise SystemExit(0 if sys.version_info[0] >= 3 else 1)' >/dev/null 2>&1; then
    PYTHON_BIN="$c"
    break
  fi
done
python_found=0; [[ -n "$PYTHON_BIN" ]] && python_found=1
have_module() { [[ $python_found -eq 1 ]] && "$PYTHON_BIN" -c "import $1" >/dev/null 2>&1; }

# --- OS / package manager ---------------------------------------------------
detect_os() {
  case "${OSTYPE:-}" in
    darwin*)             echo macos;   return ;;
    msys*|cygwin*|win32) echo windows; return ;;
  esac
  case "$(uname -s 2>/dev/null || echo)" in
    Darwin)               echo macos;   return ;;
    MINGW*|MSYS*|CYGWIN*) echo windows; return ;;
    Linux)
      if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release 2>/dev/null || true
        case " ${ID:-} ${ID_LIKE:-} " in
          *debian*|*ubuntu*)         echo debian; return ;;
          *fedora*|*rhel*|*centos*)  echo fedora; return ;;
          *arch*)                    echo arch;   return ;;
        esac
      fi
      echo linux; return ;;
  esac
  echo unknown
}
OS="$(detect_os)"

# --- tool availability ------------------------------------------------------
pandoc_found=0;      have pandoc && pandoc_found=1
pymarkdown_found=0;  have_module markdown && pymarkdown_found=1
# weasyprint counts if EITHER the CLI is on PATH (what pandoc's --pdf-engine and
# the standalone HTML->PDF path use) OR the python module is importable.
weasyprint_found=0;  { have weasyprint || have_module weasyprint; } && weasyprint_found=1
xelatex_found=0;     have xelatex && xelatex_found=1
pdflatex_found=0;    have pdflatex && pdflatex_found=1
tectonic_found=0;    have tectonic && tectonic_found=1
typst_found=0;       have typst && typst_found=1
wkhtmltopdf_found=0; have wkhtmltopdf && wkhtmltopdf_found=1

# --- choose HTML engine (always resolves to a usable rung) ------------------
if   [[ $pandoc_found     -eq 1 ]]; then html_engine="pandoc"
elif [[ $python_found -eq 1 && $pymarkdown_found -eq 1 ]]; then html_engine="python-markdown"
elif [[ $python_found -eq 1 ]]; then html_engine="builtin"
else html_engine="agent"  # no pandoc, no Python — agent authors the HTML directly
fi

# --- choose PDF engine ------------------------------------------------------
choose_pdf() {
  if [[ $pandoc_found -eq 1 ]]; then
    [[ $weasyprint_found  -eq 1 ]] && { echo "pandoc+weasyprint";  return; }
    [[ $xelatex_found     -eq 1 ]] && { echo "pandoc+xelatex";     return; }
    [[ $tectonic_found    -eq 1 ]] && { echo "pandoc+tectonic";    return; }
    [[ $typst_found       -eq 1 ]] && { echo "pandoc+typst";       return; }
    [[ $pdflatex_found    -eq 1 ]] && { echo "pandoc+pdflatex";    return; }
    [[ $wkhtmltopdf_found -eq 1 ]] && { echo "pandoc+wkhtmltopdf"; return; }
  fi
  # Standalone HTML->PDF converters that render.sh feeds from the HTML ladder.
  [[ $weasyprint_found  -eq 1 ]] && { echo "weasyprint";  return; }
  [[ $wkhtmltopdf_found -eq 1 ]] && { echo "wkhtmltopdf"; return; }
  [[ $typst_found       -eq 1 ]] && { echo "typst";       return; }
  echo "html-print"  # no PDF toolchain; HTML always works — user prints to PDF
}
pdf_engine="$(choose_pdf)"

# --- machine-readable result ------------------------------------------------
echo "os=$OS"
echo "python=$([[ $python_found -eq 1 ]] && echo "$PYTHON_BIN" || echo missing)"
echo "html_engine=$html_engine"
echo "pdf_engine=$pdf_engine"

# --- OS-correct install hints ----------------------------------------------
# hint <tool>  ->  prints the recommended install command(s) for this OS.
hint() {
  case "$1:$OS" in
    pandoc:macos)      echo "brew install pandoc" ;;
    pandoc:debian)     echo "sudo apt install pandoc" ;;
    pandoc:fedora)     echo "sudo dnf install pandoc" ;;
    pandoc:arch)       echo "sudo pacman -S pandoc" ;;
    pandoc:windows)    echo "winget install --id JohnMacFarlane.Pandoc  (or: choco install pandoc)" ;;
    pandoc:*)          echo "see https://pandoc.org/installing.html" ;;

    weasyprint:macos)  echo "pipx install weasyprint  (or: brew install weasyprint)" ;;
    weasyprint:debian) echo "pipx install weasyprint  (system libs: sudo apt install libpango-1.0-0 libpangoft2-1.0-0)" ;;
    weasyprint:fedora) echo "pipx install weasyprint  (system libs: sudo dnf install pango)" ;;
    weasyprint:arch)   echo "sudo pacman -S python-weasyprint" ;;
    weasyprint:windows)echo "pip install weasyprint  (see weasyprint docs for GTK runtime)" ;;
    weasyprint:*)      echo "pipx install weasyprint" ;;

    typst:macos)       echo "brew install typst" ;;
    typst:debian)      echo "see https://github.com/typst/typst/releases (or: cargo install typst-cli)" ;;
    typst:fedora)      echo "sudo dnf install typst  (or cargo install typst-cli)" ;;
    typst:arch)        echo "sudo pacman -S typst" ;;
    typst:windows)     echo "winget install --id Typst.Typst" ;;
    typst:*)           echo "see https://github.com/typst/typst" ;;

    tex:macos)         echo "brew install basictex  (or: brew install --cask mactex-no-gui)" ;;
    tex:debian)        echo "sudo apt install texlive-xetex" ;;
    tex:fedora)        echo "sudo dnf install texlive-xetex" ;;
    tex:arch)          echo "sudo pacman -S texlive-bin texlive-latex" ;;
    tex:windows)       echo "install MiKTeX: winget install --id MiKTeX.MiKTeX" ;;
    tex:*)             echo "install a TeX distribution (xelatex)" ;;

    python:macos)      echo "brew install python  (usually preinstalled)" ;;
    python:debian)     echo "sudo apt install python3" ;;
    python:fedora)     echo "sudo dnf install python3" ;;
    python:arch)       echo "sudo pacman -S python" ;;
    python:windows)    echo "winget install --id Python.Python.3  (or use WSL)" ;;
    python:*)          echo "install Python 3 from https://www.python.org/downloads/" ;;
  esac
}

# --- human-readable summary -------------------------------------------------
fm() { [[ $1 -eq 1 ]] && echo found || echo missing; }
{
  echo "render tool probe (os=$OS):"
  echo "  python 3:        $([[ $python_found -eq 1 ]] && echo "found ($PYTHON_BIN)" || echo missing)"
  echo "  pandoc:          $(fm $pandoc_found)"
  echo "  python markdown: $(fm $pymarkdown_found)"
  echo "  weasyprint:      $(fm $weasyprint_found)"
  echo "  xelatex:         $(fm $xelatex_found)"
  echo "  tectonic:        $(fm $tectonic_found)"
  echo "  typst:           $(fm $typst_found)"
  echo "  pdflatex:        $(fm $pdflatex_found)"
  echo "  wkhtmltopdf:     $(fm $wkhtmltopdf_found)"
  echo "  -> html engine:  $html_engine"
  echo "  -> pdf engine:   $pdf_engine"
  if [[ $python_found -eq 0 ]]; then
    echo "  warning: no Python 3 interpreter found."
    echo "    The scripted HTML renderer (md_to_html.py) cannot run; the agent will"
    echo "    author HTML directly instead. Install Python 3 to enable scripted export:"
    echo "      python3:   $(hint python)"
  fi
  if [[ "$pdf_engine" == "html-print" ]]; then
    echo "  note: no PDF toolchain found. HTML still works; install one of these for PDF:"
    echo "      pandoc:    $(hint pandoc)"
    echo "      weasyprint:$(hint weasyprint)"
    echo "      typst:     $(hint typst)"
    echo "      xelatex:   $(hint tex)"
  fi
} >&2

exit 0
