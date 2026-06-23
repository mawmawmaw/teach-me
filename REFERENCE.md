# teach-me — Reference

Schemas, commands, and patterns for the `teach-me` skill. Read this on first use.

## Course directory layout

```
course-<slug>/
├── outline.md                       # course outline (## modules, ### lessons)
├── progress.json                    # tracking state — see schema below
├── summary.md                       # written at the end of the course
└── modules/
    ├── 01-foundations/
    │   ├── 01-glossary.md
    │   ├── 01-glossary.html         # if "html" in output_formats
    │   ├── 01-glossary.pdf          # if "pdf" in output_formats and a PDF engine exists
    │   ├── 02-overview.md
    │   └── ...
    └── 02-<module-slug>/
        ├── 01-<lesson-slug>.md
        └── ...
```

`<slug>` is a kebab-case version of the topic (e.g., `"Clojure macros"` → `clojure-macros`). Lesson and module folders are zero-padded so they sort correctly.

Lesson `.md` files for a module are written only when that module starts (Step 5.1) — they do not all exist after Step 4.

## `progress.json` schema

```json
{
  "course": {
    "slug": "clojure-macros",
    "topic": "Clojure macros",
    "language": "English",
    "baseline_level": "intermediate",
    "output_formats": ["markdown", "html", "pdf"],
    "html_engine": "pandoc",
    "pdf_engine": "pandoc+weasyprint",
    "created_at": "2026-05-12T14:30:00Z",
    "updated_at": "2026-05-12T15:10:00Z"
  },
  "baseline_assessment": {
    "rounds": [
      {
        "round": 1,
        "questions": [/* same shape as a lesson evaluation.questions entry */]
      }
    ],
    "derived_level": "intermediate",
    "calibration_notes": "Solid on syntax-quote basics; shaky on hygiene/gensyms and macroexpansion order — open Module 1 with a hygiene refresher.",
    "completed_at": "2026-05-12T14:32:00Z"
  },
  "current_lesson": "01-foundations/02-overview",
  "modules": [
    {
      "id": "01-foundations",
      "title": "Foundations",
      "lessons_generated_at": "2026-05-12T14:35:00Z",
      "read_confirmed_at": "2026-05-12T14:50:00Z",
      "lessons": [
        {
          "id": "01-glossary",
          "title": "Glossary",
          "status": "completed",
          "qa_phase": [
            {
              "user_question": "What's the difference between a macro and a function?",
              "claude_answer": "Functions evaluate their arguments; macros receive them unevaluated as forms ...",
              "asked_at": "2026-05-12T14:52:00Z"
            }
          ],
          "evaluation": {
            "questions": [
              {
                "id": "q1",
                "prompt": "What is a macro?",
                "options": ["A function", "A compile-time transformation", "A variable", "A namespace"],
                "correct_index": 1,
                "user_index": 1,
                "attempts": 1,
                "result": "correct"
              }
            ],
            "open_responses": [
              {
                "id": "o1",
                "prompt": "Describe a real situation where a macro is the right tool.",
                "user_answer": "<verbatim user text>"
              }
            ],
            "completed_at": "2026-05-12T14:55:00Z"
          }
        }
      ],
      "exam": {
        "written": {
          "questions": [/* same shape as lesson evaluation.questions */],
          "open_responses": [/* same shape as lesson evaluation.open_responses */],
          "completed_at": "2026-05-12T15:05:00Z"
        },
        "practical_inline": {
          "scenario_prompt": "Walk through how you'd refactor this with-open form into a macro ...",
          "transcript_summary": "User correctly identified the need for &body; missed hygiene on x; corrected after hint.",
          "completed_at": "2026-05-12T15:08:00Z"
        },
        "practical_external": {
          "assignment_prompt": "Write a `with-timing` macro that wraps a body of expressions ...",
          "acceptance_criteria": [
            "Macro expands without leaking gensym bindings",
            "Includes 3 tests covering normal, exception, and zero-body paths"
          ],
          "user_submission": "<verbatim code or file path>",
          "review_notes": "Solid; gensym hygiene correct. Suggest: also handle (try/finally) cleanup ...",
          "submitted_at": "2026-05-12T16:30:00Z",
          "reviewed_at": "2026-05-12T16:35:00Z"
        }
      }
    }
  ],
  "final_assessment": null
}
```

Field rules:

- `baseline_level` ∈ `"beginner" | "intermediate" | "advanced"`.
- `status` ∈ `"not_started" | "in_progress" | "completed"`.
- `result` ∈ `"correct" | "incorrect"`.
- `current_lesson` is a `"<module-id>/<lesson-id>"` path.
- `course.output_formats` always includes `"markdown"`; `"html"` and/or `"pdf"` are added per the user's choice in Step 3.2.
- `course.html_engine` is one of the identifiers emitted by `probe_render.sh` (`"pandoc" | "python-markdown" | "builtin"`). It is never `null` — HTML is always producible.
- `course.pdf_engine` is one of the PDF identifiers emitted by `probe_render.sh` (e.g., `"pandoc+weasyprint"`, `"pandoc+xelatex"`, `"weasyprint"`), or `"html-print"` when no PDF toolchain exists (exports fall back to HTML). May be `null` only when `"pdf"` is not in `output_formats`.
- `baseline_assessment` is `null` until Step 3.1 completes, then records the asked questions (one entry per round), the `derived_level`, and `calibration_notes` used to tune module depth.
- `modules[i].lessons_generated_at` is stamped when the batch of `.md` (and PDFs, if enabled) for that module has been written. Absence means lessons for the module have not been generated yet.
- `modules[i].read_confirmed_at` is stamped when the user confirms they've read the module's lessons (Step 5.2). Absence means the agent is still waiting on confirmation.
- `modules[i].lessons[j].qa_phase` is an append-only array of `{user_question, claude_answer, asked_at}` recording the pre-quiz Q&A. Empty array means no questions were asked.
- `modules[i].exam` is `null` until the module finishes its lessons; then it gains `written`, `practical_inline`, and `practical_external` sub-objects in turn.
- `final_assessment` is `null` until Step 6, then has the same shape as a lesson's `evaluation` block.
- All timestamps are ISO-8601 UTC.

When updating the file after any sub-step: rewrite the file atomically (read → mutate → write), preserving all existing fields. Always bump `course.updated_at`.

## File generation toolkit

The skill exports lessons through a **resilient render toolkit** built so that output never hard-fails. The core principle is a **degradation ladder**: each format tries the best available engine first and falls back down to progressively more universal ones. The two prerequisites the ladder leans on — a **Python 3 interpreter** (for `md_to_html.py`, the pip-`markdown` tier, and module-based weasyprint) and the **OS** (for correct install hints) — are probed and reported, so it degrades knowingly rather than assuming they exist.

```
PDF request:
  1. pandoc + chosen engine     (weasyprint / xelatex / tectonic / typst / pdflatex / wkhtmltopdf)
  2. HTML -> PDF                (weasyprint or wkhtmltopdf consume HTML from the HTML ladder)
  3. (none available)          -> FALL BACK TO HTML, tell the user to print-to-PDF from a browser

HTML request:
  1. pandoc --standalone        (best fidelity; needs no Python)
  2. md_to_html.py              (Python 3: `markdown` lib if importable, else the stdlib parser)
  └─ agent-authored HTML        no pandoc AND no Python — the agent writes the HTML itself

Markdown: written directly by the agent (tier 0).
```

The bottom rung matters: if even Python is absent, Claude emits a self-contained styled HTML document with no interpreter, so the never-fail guarantee holds on a bare machine. The three scripts live in `<skill_dir>/scripts/`.

### Probe: `probe_render.sh`

```sh
<skill_dir>/scripts/probe_render.sh
```

Prints `key=value` lines on stdout and a found/missing summary + **OS-correct** install hints on stderr. It installs nothing.

```
os=macos | debian | fedora | arch | linux | windows | unknown
python=<interpreter>|missing                            # python3, then python (>=3); else missing
html_engine=pandoc | python-markdown | builtin | agent  # never empty; `agent` = no pandoc & no Python
pdf_engine=pandoc+weasyprint | pandoc+xelatex | pandoc+tectonic | pandoc+typst
         | pandoc+pdflatex | pandoc+wkhtmltopdf | weasyprint | wkhtmltopdf | typst
         | html-print                                    # no PDF toolchain; HTML + print-to-PDF
```

- Exit `0` always (HTML is always available — scripted or, as a last resort, agent-authored); exit `64` only on usage error.
- `python=` reports the interpreter the scripts will use (`python3` preferred, else `python` if it is version 3+). When it is `missing`, `html_engine` is `agent` and the agent must author HTML directly.
- `os=` drives the install hints on stderr — `brew`/`apt`/`dnf`/`pacman`/`winget` as appropriate — so the agent quotes commands that actually work on the user's platform.
- PDF probe order prefers `pandoc + weasyprint` (small footprint, best CSS), then the TeX family (`xelatex → tectonic → typst → pdflatex`), then `wkhtmltopdf`, then standalone HTML→PDF tools. `weasyprint` is detected via **either** its CLI on `PATH` (what pandoc's `--pdf-engine` and the standalone path invoke) **or** the importable Python module.

### Converter: `render.sh`

```sh
RENDER_ENGINE="<engine id>" <skill_dir>/scripts/render.sh <path/to/file.md> <html|pdf>
```

- `RENDER_ENGINE` is an optional hint (pass `course.pdf_engine` for `pdf`, `course.html_engine` for `html`); if omitted or stale, `render.sh` self-probes.
- It walks the ladder above, honoring the probed engine — e.g. it correctly drives `--pdf-engine=xelatex` when xelatex is the chosen engine (the old converter hardcoded weasyprint and silently failed otherwise).
- A `pdf` request with **no** PDF engine falls back to writing `.html` and says so.
- It auto-detects the Python interpreter (`python3`, else `python` ≥ 3) for the `md_to_html.py` tiers.
- **Read stdout** — it reports the format+engine actually used, so the agent can tell the user accurately:
  - `wrote lesson.pdf via pandoc+weasyprint`
  - `wrote lesson.html via builtin (pdf engine unavailable — print to PDF from a browser)`
  - `needs-agent-html (no pandoc and no Python 3 — author the HTML document directly)`
- Exit codes:
  - `0` — an artifact was written (possibly a fallback format).
  - `4` — a scripted renderer was available but failed (effectively never).
  - **`5` — no scripted renderer (no pandoc, no Python): the agent must author the HTML document itself.** This is the bottom rung, not an error. Write a clean self-contained `<lesson>.html` (one `<style>` block, no external assets); the CSS in `md_to_html.py` is a good basis for a consistent look.
  - `64` — usage error.
- The agent treats exit `4` as "skip export for this lesson; tell the user; keep going" and exit `5` as "author the HTML yourself" — **never block lesson progression on an export failure**.

### Stdlib renderer: `md_to_html.py`

```sh
<skill_dir>/scripts/md_to_html.py <file.md> [-o out.html] [--title "..."] [--builtin]
```

Imports only the standard library. Renders headings, paragraphs, bold/italic/inline-code, links, fenced code blocks, ordered/unordered lists, blockquotes, horizontal rules, and simple pipe tables into a self-contained, print-friendly HTML document with embedded CSS. If the third-party `markdown` library is importable it is used for richer parsing; `--builtin` forces the stdlib path (used to verify the zero-dependency floor). `render.sh` calls this as the HTML tiers; it is also fine to run directly.

### Install-on-the-spot flow (PDF requested, none found)

When the user wants PDF but `pdf_engine=html-print`:

1. Tell the user which tools are missing and quote the install hints from `probe_render.sh` stderr.
2. `AskUserQuestion`: "Install a PDF toolchain now, or export HTML (print-to-PDF from a browser)?"
3. If install: run only the commands the user approves, re-probe, and update `course.pdf_engine`.
4. If not: keep `"pdf"` in `output_formats`; `render.sh` exports HTML automatically. (Optionally the user may switch to `"html"` explicitly.)

## Module loop semantics

The skill processes one module at a time (Step 5):

```
for each module in outline:
  5.1  generate every lesson .md (and PDF if enabled) for THIS module
  5.2  announce readiness; wait for user to confirm they've read it
  5.3  for each lesson:
         Q&A phase (free-form)  →  lesson quiz (AskUserQuestion)
  5.4  module exam:
         written (AskUserQuestion)  →
         practical_inline (chat scenario)  →
         practical_external (take-home assignment + review)
  5.5  loop to next module
```

Module N+1's lesson files are not written until module N's exam (including the external assignment review) is complete. This keeps the user from being overwhelmed and lets the agent calibrate later modules to the learner's observed performance.

When resuming (Step 1), the agent picks up at the most-advanced incomplete sub-step:

1. `modules[i].exam.practical_external.user_submission` present but no `review_notes` → resume at review.
2. `modules[i].exam.practical_inline` started but no `completed_at` → resume the inline scenario.
3. `modules[i].exam.written` started but no `completed_at` → resume the written exam.
4. Some lesson in module `i` has `evaluation` started but not `completed_at` → resume the quiz.
5. A lesson has `qa_phase` entries but no `evaluation` yet → resume Q&A (ask the user if they want to continue Q&A or move to the quiz).
6. `modules[i].read_confirmed_at` is null and `lessons_generated_at` is set → resume the "waiting on user to confirm reading" wait.
7. `modules[i].lessons_generated_at` is null → resume at 5.1 for that module.

## Baseline assessment (Step 3.1)

The baseline questionnaire calibrates the whole course, so it is deeper than a single pass:

- **Round 1:** 6–10 multiple-choice questions, count scaled to topic breadth/complexity. Cover *breadth* (several subtopics) and *depth* (a few harder items to find the user's ceiling).
- **Round 2 (only if Round 1 is borderline/mixed):** up to ~4 targeted follow-ups at the suspected level to refine. Skip when Round 1 is decisive — don't pad.
- Derive `beginner | intermediate | advanced`, but also record `calibration_notes` naming specific weak/strong areas. Use those notes to set the **first module's** depth and to tune later modules — calibration is to *observed knowledge*, not just the bucket label.
- The same quality rules below apply (randomized correct-answer position, plausible distractors, no giveaways).

## Question style

For the baseline assessment, per-lesson quizzes, per-module written exams, and the final assessment:

- **Randomize the position of the correct answer.** Across a 4-question quiz, the correct index should vary — not always `0`, not always at the same spot.
- **Distractors must be plausible** at the learner's level. No joke options, no "all of the above" giveaways, no obviously-wrong filler.
- **Open-ended questions ask for application or reflection**, not recall. Good: "Sketch a case where you'd reach for X instead of Y." Bad: "What is X?"
- Calibrate difficulty to `baseline_level`. A `beginner` shouldn't get advanced edge cases on lesson 1. By the module exam, calibrate to *observed* performance in the lesson quizzes, not just the baseline.

## Feedback patterns

- **Correct answer** → short confirmation + one-line "why this is right". Keep it brief.
- **Incorrect answer** → name the misconception, point to the relevant section of the lesson by heading, allow one retry, then advance. Do not loop indefinitely.
- **Open-ended response** → acknowledge it, then provide a constructive expansion. Do not grade pass/fail.
- **Q&A phase** → answer the user's question directly and concisely; offer to go deeper if they want; never preempt the upcoming quiz by drilling on it.

## Practical assignment patterns

The module exam includes both an inline practical (Step 5.4.2) and an external take-home assignment (Step 5.4.3). They serve different purposes:

- **Inline practical** — tests *immediate* application under light pressure. Pose a scenario that takes a few turns to work through. Give corrections turn by turn. Aim for ~5–15 minutes of chat. Good shape: "Here's a situation X. What would you do, and why?"
- **External assignment** — tests *deeper* application without time pressure. Sized to the topic and `baseline_level`: a beginner module might ask for a single small artifact (50-line program, one-page write-up); an advanced module might ask for a multi-part exercise. Always provide explicit acceptance criteria so the user knows when they're done.

When reviewing the external submission:

- Read it carefully against the acceptance criteria.
- Note what's correct and *why* (positive reinforcement of right patterns).
- Identify the most important improvement, not every minor nit. One or two substantive suggestions beats a list of ten small ones.
- Do **not** issue a pass/fail grade. The point is to develop the user, not gate them.

If the user wants to defer the external assignment, save state and let them resume later (the resume order in [Module loop semantics](#module-loop-semantics) handles this).

## Source citation rules

Every lesson ends with a `## Sources` section listing 2–3 references. Prefer in this order:

1. Primary sources (original paper, RFC, official spec).
2. Official documentation from the maintainer.
3. Peer-reviewed papers or recognized textbooks.
4. Reputable secondary sources (well-regarded blogs, conference talks).

For web sources, include a stable URL and the access date (`accessed YYYY-MM-DD`). Never invent references — if you can't find a real source for a claim, weaken the claim or omit it.
