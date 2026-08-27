---
name: linux-kernel-learning
description: Plan, run, review, and advance an evidence-driven theory-plus-practice ARM64 Linux kernel learning program in this QEMU/GDB repository and its Notion learning workspace. Use when reviewing an Axx learning report, diagnosing the lab environment, creating the next kernel lab, updating learning progress, or selecting a module for deeper stability study. Do not use for unrelated application development or for claiming an experiment passed without runtime evidence.
---

# Linux Kernel Learning

Treat learning as a repeatable evidence loop:

1. Read the current action page and learner report.
2. Check each claim against source, a reproducible command, or runtime evidence.
3. Record corrections without inventing missing observations.
4. Decide `通过` or `需补充` using [references/review-rubric.md](references/review-rubric.md).
5. Create the next Axx lab only after identifying the learner's current gaps.

## Route the request

- For report review, follow **Review a report**.
- For a new lesson, follow **Create the next lab**.
- For environment problems, follow **Diagnose the lab**.
- For a long-term roadmap or module choice, follow **Advance the curriculum**.

Read [references/project-workflow.md](references/project-workflow.md) before modifying the repository or Notion.

## Review a report

1. Fetch both the Axx action page and report. Keep instructions under `01 行动项目` and learner evidence under `02 学习报告`.
2. Identify the exact kernel release, Git commit, config, module build, and QEMU run that produced each observation. Flag mixed evidence from different builds.
3. Check conceptual statements against the referenced source symbol and the observed call stack or trace.
4. Preserve original command output. Fix import-only formatting, headings, code fences, numbering, and checkboxes.
5. Add a review section with: verdict, score, confirmed strengths, concept corrections, missing evidence, and a smallest-possible resubmission checklist.
6. Mark `通过` only when all hard gates in the rubric have evidence.

## Create the next lab

1. Select one main concept and one stability-engineering question from the last review gaps.
2. Use [references/lab-authoring.md](references/lab-authoring.md) to create `labs/Axx/README.md`, source, and Kbuild Makefile.
3. Provide a theory-to-source-to-observation chain. Include at least one normal path, one cleanup or failure path, and one dynamic observation with GDB, ftrace, tracepoints, or logs.
4. Keep fault injection inside QEMU. Do not run destructive or intentionally hanging experiments on the host or original VM checkout.
5. Build and run the lab against the declared kernel before publishing. If runtime validation is unavailable, label it `未验证`.
6. Create a matching Notion action page and a separate report template with acceptance gates.

## Diagnose the lab

1. Inspect Git root, branch, dirty state, remote baseline, active QEMU/tmux process, ports, tool versions, kernel artifacts, and guest mounts before changing anything.
2. Preserve a dirty or ahead checkout. Use an independent clean checkout or branch for changes.
3. Run `./scripts/check.sh` and `./main.sh doctor`; then validate the smallest failing end-to-end path.
4. Separate host build failures, QEMU transport/boot failures, guest runtime failures, and debugger-symbol/address failures.
5. Record exact commands, output, root cause, fix, and post-fix evidence.

## Advance the curriculum

- Prefer depth over topic hopping: execution context -> scheduling/synchronization -> memory -> VFS/block -> networking -> tracing/crash analysis -> one subsystem specialty.
- Tie each lab to a stability failure mode such as lost wakeups, lifetime bugs, lock ordering, use-after-free, refcount errors, or memory corruption.
- Require a learner report and review before closing each Axx item.
- Carry unresolved questions into the next lesson's prerequisites; do not silently mark them learned.
