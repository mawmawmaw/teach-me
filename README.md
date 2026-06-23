# teach-me

An **agent skill** that turns an AI coding assistant into a personal tutor. Give it a topic and it builds a bespoke, multi-lesson course — calibrated to what you already know — then teaches it lesson by lesson with quizzes, exams, and hands-on assignments, tracking your progress so you can stop and resume anytime.

It's built on the portable [`SKILL.md`](https://code.claude.com/docs/en/skills) format (a Markdown instruction file plus a few plain bash/Python scripts), so it runs in **any agent that supports skills** — [Claude Code](https://code.claude.com/docs/en/overview) is one, but nothing here is Claude-specific. The workflow is the instructions; the scripts are ordinary tools any harness can run.

Courses are written as Markdown in your working directory and can optionally be exported to **HTML or PDF** through a resilient render toolkit that never hard-fails, whatever tooling you have installed.

---

## What it does

- **Baseline assessment** — a deeper, adaptive questionnaire (6–10 questions, with an optional targeted follow-up round) figures out whether you're a beginner, intermediate, or advanced learner and notes your weak/strong areas, so lessons land at the right depth.
- **Structured course** — opens with a glossary, then builds up through modules of 2–5 lessons each, every lesson building on the last. Content is researched from up-to-date sources and every lesson cites real references.
- **Active learning** — a free-form Q&A phase before each quiz, per-lesson multiple-choice + reflection quizzes, and per-module exams with three parts: a written exam, an inline practical scenario, and a take-home assignment that the agent reviews.
- **Progress tracking** — everything is saved to `progress.json`. Close the session and come back later; the skill resumes from the exact sub-step you left off at.
- **Optional export** — render any lesson (and the final summary) to HTML and/or PDF. See [The render toolkit](#the-render-toolkit).

## Installation

Clone the skill into the directory your agent loads skills from. The exact path depends on your tool — for **Claude Code** that's `~/.claude/skills/`:

```sh
git clone https://github.com/mawmawmaw/teach-me.git ~/.claude/skills/teach-me
```

For another harness, clone it anywhere and point your agent at it (or symlink it into that tool's skills directory):

```sh
git clone https://github.com/mawmawmaw/teach-me.git
ln -s "$PWD/teach-me" /path/to/your-agent/skills/teach-me
```

Your agent discovers it on the next session. The skill sets `disable-model-invocation: true` in its frontmatter, so harnesses that honor that flag only run it when you ask for it explicitly.

## Usage

Start your agent in the directory where you want the course saved, then ask for the skill explicitly — invoke it by name (e.g. `/teach-me` in Claude Code) or just tell the agent what you want to learn, e.g. *"teach me Clojure macros."* It will:

1. Ask your course language, topic, and learning goals.
2. Run the baseline assessment and ask which export formats you want.
3. Design an outline, then teach module by module — generating lessons, waiting for you to read, running Q&A, quizzes, and the module exam before moving on.

To **resume**, start your agent in the same directory and invoke the skill again; it finds the existing `course-*/` folder and picks up where you stopped.

A course lives in its own directory:

```
course-<topic-slug>/
├── outline.md          # the course plan
├── progress.json       # tracking state (resume point, scores, engines)
├── summary.md          # key takeaways + next steps, written at the end
└── modules/
    └── 01-foundations/
        ├── 01-glossary.md
        ├── 01-glossary.html     # if HTML export is enabled
        └── 01-glossary.pdf      # if PDF export is enabled and an engine exists
```

## The render toolkit

Exports go through a **degradation ladder** so output never hard-fails — it always produces *something* readable, using the best engine available and quietly falling back when one is missing.

```
PDF:   pandoc + engine (weasyprint / xelatex / tectonic / typst / …)
        → HTML → PDF (weasyprint / wkhtmltopdf)
        → fall back to HTML (print to PDF from any browser)

HTML:  pandoc --standalone
        → md_to_html.py (Python: `markdown` lib if present, else a stdlib parser)
        → agent-authored HTML (the agent writes it directly — needs no tooling at all)
```

The toolkit probes for what's installed — including whether a **Python 3** interpreter exists and **which OS** you're on — and surfaces platform-correct install hints (`brew` / `apt` / `dnf` / `pacman` / `winget`) when you opt into PDF. If you have nothing installed, you still get a clean, self-contained, print-ready HTML file.

### Scripts

| Script | Role |
|--------|------|
| `scripts/probe_render.sh` | Detects OS, Python, and the available HTML/PDF engines; emits install hints. |
| `scripts/render.sh` | Converts a `.md` file to HTML or PDF, walking the fallback ladder. |
| `scripts/md_to_html.py` | Stdlib-only Markdown → self-contained styled HTML (the zero-dependency floor). |
| `scripts/init_progress.py` | Builds the initial `progress.json` from a course outline. |

## Requirements

- **An agent that supports the `SKILL.md` skill format** and can run bash/Python scripts (e.g. Claude Code).
- **Nothing else is strictly required** — Markdown always works, and HTML works with just Python 3 (or even without it, via agent-authored HTML).
- **Optional, for richer export:** [`pandoc`](https://pandoc.org), and a PDF engine such as [`weasyprint`](https://weasyprint.org), a TeX distribution (`xelatex`/`tectonic`), or [`typst`](https://typst.app). The skill will offer to install one for you if you choose PDF and none is found.

## How it's structured

- [`SKILL.md`](SKILL.md) — the skill instructions the agent follows (the workflow).
- [`REFERENCE.md`](REFERENCE.md) — schemas, the render toolkit spec, question/feedback patterns, and the `progress.json` format.
- [`scripts/`](scripts) — the render toolkit and progress initializer.

## License

MIT
