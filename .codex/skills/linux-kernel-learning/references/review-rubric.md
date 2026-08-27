# Review rubric

Score out of 100:

- Environment and reproducibility: 15
- Theory and source understanding: 20
- Source navigation: 15
- Runtime experiment: 20
- Dynamic debugging or tracing: 15
- Failure analysis and recovery: 10
- Report clarity and evidence labeling: 5

## Hard gates

A report is `需补充` regardless of score when any of these is missing:

- exact kernel release and experiment Git commit;
- evidence that the module or reproducer ran in the declared QEMU guest;
- a normal path and the requested cleanup/failure path;
- at least one dynamic source-to-runtime observation;
- explanations are materially inconsistent with the supplied evidence;
- evidence from multiple kernel builds is mixed without labels.

Use `通过` at 80 or above when every hard gate passes. Do not fill missing learner answers on their behalf. Give the smallest resubmission checklist that can close the gaps.
