# Project workflow

## Repository boundaries

- Public repository: `Colin-Cai0318/qemu-gdb-kernel-ARM-`.
- Use a scoped feature branch based on the current remote default branch.
- Do not commit downloaded kernel/BusyBox sources, build objects, modules, logs, credentials, private keys, VM addresses, or account names.
- Treat an existing dirty or ahead checkout as learner-owned evidence. Do not clean, reset, or overwrite it.
- Validate in a clean independent checkout when the learner's checkout is not clean.

## Notion structure

- Root: `ARM64 Linux 内核理论与实践`.
- `01 行动项目`: instructions, theory, commands, acceptance criteria, and next-step link.
- `02 学习报告`: learner answers, raw evidence, failures, conclusions, review, and resubmission status.
- Name items with stable IDs: `A01`, `A02`, and so on.
- Search and fetch before editing. Preserve child pages and useful learner evidence.

## Evidence contract

Every material conclusion should have at least one of:

- a kernel source path and symbol;
- a reproducible command plus relevant output;
- a GDB stack/register observation;
- an ftrace/tracepoint/log timeline;
- a controlled bad-path and recovery comparison.

Keep kernel release, Git commit, `.config`, `vermagic`, and runtime log from the same build chain. If they differ, label the evidence sets separately.
