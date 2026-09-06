"""Synthetic negative evidence and launcher failure tests, not guest evidence."""

import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("a02_check", ROOT / "labs/A02/check-output.py")
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)

# Deliberately synthetic trace used only to test rejection/acceptance rules.
VALID = """A02_WORKER_PID=42
A02_TRACE_BEGIN
 init-1 [000] 1.000: sched_waking: comm=a02_worker pid=42 prio=120
 init-1 [000] 1.001: sched_wakeup: comm=a02_worker pid=42 prio=120
 init-1 [000] 1.002: sched_switch: prev_comm=init prev_pid=1 prev_state=S ==> next_comm=a02_worker next_pid=42
 a02_worker-42 [000] 1.003: sched_switch: prev_comm=a02_worker prev_pid=42 prev_prio=120 prev_state=S ==> next_comm=swapper/0 next_pid=0
A02_TRACE_END
A02_TRACEPOINT_PASS
A02_CLEANUP_PASS
A02_BOUNDED_STOP_PASS
A02_IDLE_STOP_PASS
A02_DMESG_BEGIN
[1] sched_lab: worker-start pid=42
[2] sched_lab: worker-stop handled=3 pid=42
[3] sched_lab: unloaded pid=7
[4] sched_lab: worker-start pid=43
[5] sched_lab: worker-stop handled=2 pid=43
[6] sched_lab: unloaded pid=8
[7] sched_lab: worker-start pid=44
[8] sched_lab: worker-stop handled=0 pid=44
[9] sched_lab: unloaded pid=9
A02_DMESG_END
A02_RUNTIME_PASS
"""


class EvidenceTests(unittest.TestCase):
    def test_complete_evidence(self):
        CHECK.validate(VALID)
        CHECK.validate(VALID.replace("\n", "\r\n"))

    def test_each_trace_event_is_required(self):
        for event in ("sched_waking:", "sched_wakeup:", "next_comm=a02_worker", "prev_state=S ==> next_comm=swapper"):
            with self.subTest(event=event), self.assertRaises(ValueError):
                CHECK.validate(VALID.replace(event, "removed:"))

    def test_unrelated_pid_does_not_pass(self):
        with self.assertRaises(ValueError):
            CHECK.validate(VALID.replace("sched_wakeup: comm=a02_worker pid=42", "sched_wakeup: comm=a02_worker pid=99"))

    def test_events_must_be_in_order(self):
        lines = VALID.splitlines()
        lines[2], lines[3] = lines[3], lines[2]
        with self.assertRaises(ValueError):
            CHECK.validate("\n".join(lines))

    def test_each_pass_marker_is_required(self):
        for line in VALID.splitlines():
            if line.endswith("_PASS"):
                with self.subTest(marker=line), self.assertRaises(ValueError):
                    CHECK.validate(VALID.replace(line, ""))

    def test_panic_after_pass_is_failure(self):
        for error in ("Kernel panic", "WARNING:", "BUG:", "Oops:", "KASAN:", "A02_RUNTIME_FAIL"):
            with self.subTest(error=error), self.assertRaises(ValueError):
                CHECK.validate(VALID + error)

    def test_reversed_unload_is_failure(self):
        with self.assertRaises(ValueError):
            CHECK.validate(VALID.replace("worker-stop handled=3", "unloaded").replace("unloaded pid=7", "worker-stop handled=3 pid=42"))

    def test_drained_backlog_is_not_cancellation(self):
        with self.assertRaises(ValueError):
            CHECK.validate(VALID.replace("handled=2", "handled=33"))

    def test_wrong_normal_or_idle_counts(self):
        for old, new in (("handled=3", "handled=2"), ("handled=0", "handled=1")):
            with self.subTest(old=old), self.assertRaises(ValueError):
                CHECK.validate(VALID.replace(old, new))

    def test_pass_text_alone_is_insufficient(self):
        with self.assertRaises(ValueError):
            CHECK.validate("A02_TRACEPOINT_PASS\nA02_RUNTIME_PASS\n")


@unittest.skipUnless(os.name == "posix" and shutil.which("cpio"), "Linux launcher tools required")
class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="a02-launcher-test-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.repo = self.base / "repo"
        lab = self.repo / "labs/A02"
        lab.mkdir(parents=True)
        for name in ("validate-qemu.sh", "validate-init.sh", "check-output.py", "sched_lab.c"):
            shutil.copy2(ROOT / "labs/A02" / name, lab / name)
        (lab / "sched_lab.ko").write_bytes(b"test-module")
        self.kernel = self.base / "kernel"
        for path, content in (("arch/arm64/boot/Image", "test-image"), ("vmlinux", "test-elf"), ("include/config/kernel.release", "6.12.0"), (".config", "test-config")):
            target = self.kernel / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content)
        rootfs = self.base / "rootfs"
        (rootfs / "bin").mkdir(parents=True)
        shutil.copy2("/bin/true", rootfs / "bin/busybox")
        bindir = self.base / "bin"
        bindir.mkdir()
        mocks = {
            "file": "#!/bin/sh\necho 'ELF ARM aarch64'\n",
            "modinfo": "#!/bin/sh\necho \"${TEST_RELEASE:-6.12.0} SMP aarch64\"\n",
            "test-qemu": "#!/bin/sh\nif [ \"${1:-}\" = --version ]; then echo test-qemu; exit 0; fi\ncat \"$TEST_FIXTURE\"\nsleep \"${TEST_DELAY:-0}\"\nexit \"${TEST_EXIT:-0}\"\n",
        }
        for name, body in mocks.items():
            path = bindir / name
            path.write_text(body)
            path.chmod(0o755)
        fixture = self.base / "fixture.txt"
        fixture.write_text(VALID)
        self.env = dict(os.environ, KDIR=str(self.kernel), ROOTFS_STAGING=str(rootfs),
                        QEMU_BIN=str(bindir / "test-qemu"), TEST_FIXTURE=str(fixture),
                        PATH=str(bindir) + os.pathsep + os.environ["PATH"])
        subprocess.run(["git", "init", "-q", str(self.repo)], check=True)
        subprocess.run(["git", "-C", str(self.repo), "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "--allow-empty", "-qm", "test"], check=True)

    def run_launcher(self, **env):
        return subprocess.run(["bash", str(self.repo / "labs/A02/validate-qemu.sh")], env=dict(self.env, **env),
                              capture_output=True, text=True, timeout=10)

    def test_normal_exit_retains_evidence(self):
        result = self.run_launcher()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("A02_QEMU_VALIDATION=PASS", result.stdout)
        runs = list((self.repo / "artifacts/A02").iterdir())
        self.assertEqual(len(runs), 1)
        self.assertIn("module_vermagic=6.12.0", (runs[0] / "manifest.txt").read_text())
        self.assertEqual((runs[0] / "qemu.log").read_text(), VALID)

    def test_timeout_after_pass_is_failure_and_keeps_log(self):
        result = self.run_launcher(TEST_DELAY="2", QEMU_TIMEOUT="0.1s")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("A02_QEMU_VALIDATION=PASS", result.stdout)
        self.assertIn("timeout is a failure", result.stderr)
        self.assertIn("A02_RUNTIME_PASS", result.stdout)
        self.assertTrue(list((self.repo / "artifacts/A02").glob("*/qemu.log")))

    def test_nonzero_exit_after_pass_is_failure(self):
        result = self.run_launcher(TEST_EXIT="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("QEMU/tee failed", result.stderr)
        self.assertIn("A02_RUNTIME_PASS", result.stdout)

    def test_release_mismatch_rejected_before_launch(self):
        result = self.run_launcher(TEST_RELEASE="6.1.0")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("release mismatch", result.stderr)
        self.assertFalse((self.repo / "artifacts").exists())


if __name__ == "__main__":
    unittest.main()
