#!/usr/bin/env python3
"""Validate A02 serial evidence; a printed PASS alone is not sufficient."""

import re
import sys
from pathlib import Path


def validate(output):
    output = output.replace("\r", "")
    for marker in (
        "A02_TRACEPOINT_PASS", "A02_CLEANUP_PASS", "A02_BOUNDED_STOP_PASS",
        "A02_IDLE_STOP_PASS", "A02_RUNTIME_PASS",
    ):
        if marker not in output.splitlines():
            raise ValueError(f"missing marker: {marker}")
    if re.search(r"A02_RUNTIME_FAIL|Kernel panic|BUG:|WARNING:|Oops:|KASAN:", output):
        raise ValueError("guest failure or kernel diagnostic in serial output")
    pid_match = re.search(r"^A02_WORKER_PID=(\d+)$", output, re.M)
    if not pid_match:
        raise ValueError("missing worker PID")
    pid = pid_match[1]
    trace_match = re.search(r"A02_TRACE_BEGIN\n(.*?)\nA02_TRACE_END", output, re.S)
    if not trace_match:
        raise ValueError("missing trace evidence")
    # Require the target PID, not just a comm string in an unrelated switch.
    patterns = (
        rf"sched_waking: comm=a02_worker pid={pid}\b",
        rf"sched_wakeup: comm=a02_worker pid={pid}\b",
        rf"sched_switch: .*next_comm=a02_worker next_pid={pid}\b",
        rf"sched_switch: prev_comm=a02_worker prev_pid={pid}\b.*prev_state=S",
    )
    trace = trace_match[1]
    cursor = 0
    for pattern in patterns:
        match = re.search(pattern, trace[cursor:])
        if not match:
            raise ValueError(f"missing ordered scheduler event: {pattern}")
        cursor += match.end()
    dmesg_match = re.search(r"A02_DMESG_BEGIN\n(.*?)\nA02_DMESG_END", output, re.S)
    if not dmesg_match:
        raise ValueError("missing final dmesg")
    log = dmesg_match[1]
    events = re.findall(r"sched_lab: (worker-start|worker-stop|unloaded)\b", log)
    if events != ["worker-start", "worker-stop", "unloaded"] * 3:
        raise ValueError(f"unexpected lifecycle order: {events}")
    handled = re.findall(r"sched_lab: worker-stop handled=(\d+)", log)
    if len(handled) != 3 or int(handled[0]) != 3 or not 2 <= int(handled[1]) < 33:
        raise ValueError(f"unexpected handled counts (backlog must be cancelled): {handled}")
    if int(handled[2]) != 0:
        raise ValueError("idle unload processed unexpected work")


if __name__ == "__main__":
    try:
        validate(Path(sys.argv[1]).read_text(errors="replace"))
    except (ValueError, OSError) as error:
        sys.exit(f"A02 evidence rejected: {error}")
    print("A02_EVIDENCE_PASS")
