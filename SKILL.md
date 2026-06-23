---
name: teach-me
description: Build bespoke multi-lesson courses on any topic, with baseline assessment, per-lesson quizzes, per-module exams (written + practical), progress tracking, and optional PDF/HTML export. Use when the user wants to learn a subject in depth or asks for a structured course on a topic.
disable-model-invocation: true
---

# teach-me

Produces a structured course (glossary → modules → lessons) saved as Markdown in the working directory, with per-lesson quizzes via `AskUserQuestion`, per-module exams (written + inline practical + take-home assignment), resumable progress in `progress.json`, and optional PDF/HTML export of each lesson. Exports use a resilient render toolkit that degrades gracefully — output never hard-fails, because a bundled stdlib-only HTML renderer is always available.

For the directory layout, full `progress.json` schema, PDF probe/command details, and question/feedback patterns, see [REFERENCE.md](REFERENCE.md).

## Step 1 — Resume or start fresh

Look for `course-*/progress.json` in the working directory.

- **Found** → load it, summarize the user's position ("You're on Module 2, Lesson 3 of <topic> — want to continue?"), and resume from the correct point. Resume points (in priority order): mid-exam → mid-lesson quiz → mid-Q&A → waiting on user to confirm reading → next lesson to generate. Skip to the appropriate sub-step of Step 5.
- **Not found** → continue to Step 2.

## Step 2 — Intake

Ask the user, in this order:

1. Course language (e.g., English, Spanish).
2. Topic they want to learn.
3. Learning goals — what they want to be able to do or understand by the end.

## Step 3 — Baseline assessment and output setup

### 3.1 Baseline assessment (deeper, adaptive)

1. **Round 1 — breadth + depth.** Use `AskUserQuestion` with **6–10 multiple-choice items**, count scaled to the topic's breadth and complexity. Span both *breadth* (cover several subtopics) and *depth* (include a few harder items to probe the user's ceiling). Apply the same question-quality rules as quizzes (randomized correct-answer position, plausible distractors) — see [REFERENCE.md](REFERENCE.md).

2. **Round 2 — targeted follow-up (only if needed).** If Round 1 is borderline or mixed (e.g., strong on basics but split on advanced items), ask up to ~4 more targeted questions at the suspected level to refine. Skip this round entirely if Round 1 is decisive.

3. Pick a starting level: `beginner`, `intermediate`, or `advanced`. Record the assessment in `progress.json.baseline_assessment` (asked questions, user answers, derived level, and a short `calibration_notes` string naming observed weak/strong areas). Use those notes to calibrate the **first module's** depth — not just the bucket — and revisit them when planning later modules.

### 3.2 Output format setup

1. **Ask which export formats the user wants** via `AskUserQuestion`: PDF, HTML, both, or Markdown-only. (Markdown is always written regardless.) Store the choice as `course.output_formats` (e.g., `["markdown","html","pdf"]`).

2. **Probe the render toolkit** for what's available:

   ```sh
   <skill_dir>/scripts/probe_render.sh
   ```

   It prints `key=value` lines on stdout — `os=`, `python=`, `html_engine=`, `pdf_engine=` — and a human-readable summary plus **OS-correct** install hints on stderr. Store `html_engine` and `pdf_engine` in `progress.json` (`os`/`python` are situational, not persisted).

   - **HTML is always available** (`html_engine` is never empty). If the user selected HTML, no install is ever required.
   - **`html_engine=agent`** means there is no pandoc *and* no Python 3 — the scripted renderer can't run, so **you (the agent) author the styled, self-contained HTML document directly** (see Step 5.1). The probe surfaces a Python install hint in case the user prefers scripted export.
   - If the user selected **PDF** and `pdf_engine=html-print` (no PDF toolchain found): tell the user what's missing (quote the stderr install hints, which are correct for their OS) and ask via `AskUserQuestion` whether to install one now. If yes, run only the installs the user approves, re-probe, and update `pdf_engine`. If no, explain that lessons will export to **HTML instead** (printable to PDF from any browser) and keep `pdf` in `output_formats` — `render.sh` performs the PDF→HTML fallback automatically.

See [REFERENCE.md](REFERENCE.md) → *File generation toolkit* for the full render ladder and engine ids.

## Step 4 — Plan the course (outline only)

Using up-to-date information from the web, design an outline tailored to the user's topic, goals, and baseline level:

- Open with a **glossary** lesson covering foundational terms.
- Break the rest into **modules** of 2–5 lessons each.
- Each lesson must build on the previous one.

Save the outline to `course-<slug>/outline.md` using `##` for module titles and `###` for lesson titles.

**Do not write any lesson `.md` files yet.** Lessons are generated module-by-module in Step 5.

Initialize progress tracking:

```sh
python3 <skill_dir>/scripts/init_progress.py \
  --slug <slug> --topic "<topic>" --language <lang> \
  --level <level> --formats <html,pdf | html | pdf | ""> \
  --outline course-<slug>/outline.md \
  --output course-<slug>/progress.json
```

`--formats` is the comma-separated list of export formats beyond Markdown (use `""` for Markdown-only). After `init_progress.py` runs, write the probed engine ids (`course.html_engine`, `course.pdf_engine`) and the `baseline_assessment` block into `progress.json` directly — see [REFERENCE.md](REFERENCE.md) for the full schema.

## Step 5 — Module loop

For each module in the outline, in order:

### 5.1 Generate every lesson in the module up front

- Write each lesson's Markdown to `course-<slug>/modules/<NN>-<module-slug>/<NN>-<lesson-slug>.md`. Lessons must be **thorough**: in-depth explanations, concrete real-world examples, and a `## Sources` section with 2–3 references (primary sources, official docs, peer-reviewed papers, or recognized textbooks). Do not write short or shallow lessons.
- For each export format in `course.output_formats` other than `markdown` (`html` and/or `pdf`), render each lesson:

  ```sh
  RENDER_ENGINE="<course.pdf_engine or course.html_engine>" \
    <skill_dir>/scripts/render.sh course-<slug>/modules/<NN>-<module>/<NN>-<lesson>.md <html|pdf>
  ```

  Pass the matching probed engine via `RENDER_ENGINE` (the `pdf_engine` for `pdf`, the `html_engine` for `html`); `render.sh` self-probes if it's omitted. `render.sh` prints the format+engine it actually used on stdout — **read it**: a `pdf` request with no engine falls back to writing `.html` (and says so). Relay that to the user accurately ("PDF wasn't available, exported HTML — open it in a browser and print to PDF").

  Handle its exit code:
  - **Exit 5 (`needs-agent-html`)** — no pandoc and no Python 3, so no script can render. **Author the HTML yourself**: write a clean, self-contained `<lesson>.html` (one `<style>` block, no external assets) with the lesson content. This is the true bottom rung — it keeps export working with zero tooling. (You may reuse the CSS in `scripts/md_to_html.py` for a consistent look.)
  - **Any other non-zero exit** — tell the user export failed for that lesson and continue with the `.md` only.

  **Never block lesson progression on an export failure.**
- Set each lesson's `status` to `"in_progress"` and stamp `modules[i].lessons_generated_at` in `progress.json`.

### 5.2 Announce readiness — do not ask any questions yet

Tell the user: "Module N — `<title>` is ready. The lesson files are at: `<list of paths>`. Take your time to read them, then let me know when you're done."

**Wait for a free-form user response.** Do not use `AskUserQuestion` here. Do not immediately follow up with a quiz. When the user confirms they have read the materials, stamp `modules[i].read_confirmed_at`.

### 5.3 Per-lesson loop (within the current module)

For each lesson in the current module, in order:

1. **Q&A phase**. Ask in plain prose: "Do you have any questions about `<lesson title>` before we move on to the quiz?" Answer freely. Record every Q&A turn verbatim in `progress.json` under `modules[i].lessons[j].qa_phase` as `{user_question, claude_answer, asked_at}` entries. Loop until the user says they are ready.

2. **Lesson quiz**. Use `AskUserQuestion`: 3–5 multiple-choice questions plus 1–2 open-ended reflection questions on this specific lesson. **Randomize the position of the correct answer** across questions. **Distractors must be plausible at the learner's level.** Open questions ask for application or reflection, not recall.

3. **For each incorrect answer**, explain the misconception, point to the relevant section of the lesson by heading, allow one retry, then advance.

4. **Record results** in `progress.json` under the lesson's `evaluation` block (per-question result + attempts; verbatim open-ended answers). Mark the lesson `completed`, update `current_lesson` and `updated_at`.

### 5.4 Module exam (written + practical)

Once all lessons in the module are `completed`:

1. **Written portion**. Use `AskUserQuestion` for a cross-lesson exam (5–8 multiple-choice + 1–2 open-ended) drawing from across the whole module. Same randomization and distractor rules. Record under `modules[i].exam.written`.

2. **Practical — inline portion**. Pose a concrete scenario or problem in chat that requires applying the module's content (e.g., "Walk me through how you'd model X" / "Trace what happens when Y"). The user works through it conversationally. Give constructive feedback turn by turn — do not grade pass/fail. Record a short `transcript_summary` plus the scenario prompt under `modules[i].exam.practical_inline`.

3. **Practical — external assignment**. Propose a take-home task sized to the topic and baseline level: a small program, a written artifact, a design exercise, etc. Include explicit acceptance criteria. The user completes it outside the chat and pastes or uploads their work. Review and give written feedback. Record `assignment_prompt`, `acceptance_criteria`, `user_submission`, and `review_notes` under `modules[i].exam.practical_external`.

If the user wants to defer the external assignment, save state and let them resume later — `progress.json` already supports it.

### 5.5 Next module

Once the module exam (all three parts) is complete, **loop back to 5.1 for the next module**. If this was the final module in the outline, fall through to Step 6.

## Step 6 — Wrap-up

After the final module exam:

1. Run a cross-module **final assessment** via `AskUserQuestion` (same format as the module exams' written portions, drawing from all modules). Save results to `progress.json.final_assessment`.
2. Write `course-<slug>/summary.md` containing the **key takeaways** of the course and **recommended next steps** for further study or practice, calibrated to the user's performance.
3. Export `summary.md` to each format in `course.output_formats` (other than `markdown`) with `render.sh`, exactly as in Step 5.1.

## Notes for the agent

- The course directory is `course-<slug>/` where `<slug>` is a kebab-case version of the topic.
- Always cite sources — never fabricate references.
- The schema for `progress.json`, the render toolkit (probe + `render.sh` ladder), question style, and feedback patterns are documented in [REFERENCE.md](REFERENCE.md). Read it on first use.
