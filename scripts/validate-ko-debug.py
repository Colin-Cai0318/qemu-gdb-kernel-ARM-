#!/usr/bin/env python3
"""Exercise real ARM64 QEMU + CLI GDB and VS Code's installed cppdbg adapter.

Run on Linux after building the kernel, customized/main.ko and labs A01/A02.
No VM addresses, credentials, generated binaries or logs belong in Git.
"""
import argparse
import json
import os
import pathlib
import queue
import re
import signal
import socket
import subprocess
import threading
import time


REPO = pathlib.Path(__file__).resolve().parents[1]


def wait_for(predicate, message, seconds=90):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        result = predicate()
        if result:
            return result
        time.sleep(0.1)
    raise RuntimeError('Timeout: ' + message)


class Qemu:
    def __init__(self, kernel, port, log, wait_gdb=True):
        with socket.socket() as probe:
            probe.bind(('127.0.0.1', port))
        self.output = ''
        self.log = open(log, 'w')
        env = dict(os.environ, KERNEL_DIR=str(kernel), GDB_PORT=str(port))
        command = ([str(REPO / 'qemu/runQemu.sh'), '--wait-gdb'] if wait_gdb
                   else [str(REPO / 'main.sh'), 'qemu'])
        self.proc = subprocess.Popen(command,
                                     env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.STDOUT, text=True, bufsize=1)
        threading.Thread(target=self.read, daemon=True).start()
        def listening():
            if self.proc.poll() is not None:
                raise RuntimeError('QEMU exited before opening its GDB listener: ' + self.output)
            # Do not connect to the GDB stub: GDB must be its first client.
            return '127.0.0.1:%s' % port in subprocess.check_output(['ss', '-ltnH'], text=True)
        wait_for(listening, 'QEMU GDB listener')

    def read(self):
        for char in iter(lambda: self.proc.stdout.read(1), ''):
            self.output += char
            self.log.write(char)
            self.log.flush()

    def command(self, command):
        self.proc.stdin.write(command + '\n')
        self.proc.stdin.flush()

    def ready(self):
        wait_for(lambda: 'Please press Enter' in self.output, 'Guest console')
        self.command('')
        self.command('echo KO_CONSOLE_READY')
        wait_for(lambda: re.search(r'(?m)^KO_CONSOLE_READY\r?$', self.output), 'Guest shell')

    def close(self):
        if self.proc.poll() is None:
            self.proc.terminate()
            self.proc.wait(timeout=10)
        self.log.close()


class Gdb:
    def __init__(self, kernel, setup, port, log):
        self.output = ''
        self.log = open(log, 'w')
        self.proc = subprocess.Popen(['gdb', '-q', '-nx', str(kernel / 'vmlinux'),
                                      '-x', str(setup), '-ex', 'target remote :%s' % port],
                                     cwd=kernel, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.STDOUT, text=True, bufsize=1)
        threading.Thread(target=self.read, daemon=True).start()
        wait_for(lambda: self.output.rstrip().endswith('(gdb)'), 'GDB initial prompt')

    def read(self):
        for char in iter(lambda: self.proc.stdout.read(1), ''):
            self.output += char
            self.log.write(char)
            self.log.flush()

    def send(self, command):
        self.proc.stdin.write(command + '\n')
        self.proc.stdin.flush()

    def command(self, command):
        start = len(self.output)
        self.send(command)
        wait_for(lambda: '(gdb)' in self.output[start:], 'GDB: ' + command)
        return self.output[start:]

    def hit(self, command, pattern):
        start = len(self.output)
        self.send('continue')
        command()
        wait_for(lambda: re.search(pattern, self.output[start:]), pattern)
        wait_for(lambda: '(gdb)' in self.output[start:], 'breakpoint prompt')
        return self.output[start:]

    def close(self):
        if self.proc.poll() is None:
            self.proc.terminate()
            self.proc.wait(timeout=10)
        self.log.close()


class Dap:
    def __init__(self, adapter, log):
        self.proc = subprocess.Popen([str(adapter)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=open(str(log) + '.stderr', 'w'))
        self.messages = queue.Queue()
        self.saved = []
        self.seq = 0
        self.log = open(log, 'w')
        threading.Thread(target=self.read, daemon=True).start()

    def read(self):
        while True:
            headers = {}
            while True:
                line = self.proc.stdout.readline()
                if not line:
                    return
                if line == b'\r\n':
                    break
                key, value = line.decode().split(':', 1)
                headers[key.lower()] = value.strip()
            message = json.loads(self.proc.stdout.read(int(headers['content-length'])))
            self.log.write(json.dumps(message) + '\n')
            self.log.flush()
            self.messages.put(message)

    def send(self, command, arguments=None):
        self.seq += 1
        message = {'seq': self.seq, 'type': 'request', 'command': command, 'arguments': arguments or {}}
        data = json.dumps(message).encode()
        self.proc.stdin.write(('Content-Length: %d\r\n\r\n' % len(data)).encode() + data)
        self.proc.stdin.flush()
        return self.seq

    def receive(self, predicate, seconds=90):
        deadline = time.monotonic() + seconds
        for index, message in enumerate(self.saved):
            if predicate(message):
                return self.saved.pop(index)
        while time.monotonic() < deadline:
            try:
                message = self.messages.get(timeout=max(0.1, deadline - time.monotonic()))
            except queue.Empty:
                break
            if predicate(message):
                return message
            if message.get('type') == 'response' and not message.get('success'):
                raise RuntimeError('DAP request failed: ' + json.dumps(message))
            self.saved.append(message)
        raise RuntimeError('DAP timeout; see adapter log')

    def response(self, seq):
        message = self.receive(lambda m: m.get('request_seq') == seq)
        if not message.get('success'):
            raise RuntimeError('DAP request failed: ' + json.dumps(message))
        return message.get('body', {})

    def request(self, command, arguments=None):
        return self.response(self.send(command, arguments))

    def stopped(self):
        return self.receive(lambda m: m.get('event') == 'stopped')['body']

    def close(self):
        if self.proc.poll() is None:
            self.proc.terminate()
            self.proc.wait(timeout=10)
        self.log.close()


def cli(kernel, setup, port, output):
    qemu = Qemu(kernel, port, output / 'cli-qemu.log')
    gdb = None
    try:
        gdb = Gdb(kernel, setup, port, output / 'cli-gdb.log')
        assert 'kernel-lab: watching' in gdb.output, gdb.output
        assert 'Traceback' not in gdb.output, gdb.output
        assert 'Breakpoint' in gdb.command('break start_kernel')
        gdb.send('continue')
        wait_for(lambda: re.search(r'Breakpoint [\d.]+, .*start_kernel', gdb.output), 'start_kernel')
        wait_for(lambda: gdb.output.rstrip().endswith('(gdb)'), 'start prompt')
        assert 'pending' in gdb.command('break hello_start')
        assert 'pending' in gdb.command('break hello_end')
        gdb.send('continue')
        qemu.ready()
        for cycle in range(2):
            if cycle == 0:
                start = len(gdb.output)
                qemu.command('insmod /mnt/customized/main.ko')
                wait_for(lambda: re.search(r'Breakpoint [\d.]+, .*hello_start', gdb.output[start:]), 'custom init')
            else:
                gdb.hit(lambda: qemu.command('insmod /mnt/customized/main.ko'), r'Breakpoint [\d.]+, .*hello_start')
            assert 'hello_start' in gdb.command('bt')
            assert 'customized/main.c' in gdb.command('info source')
            assert 'hello_start' in gdb.command('info line *$pc')
            gdb.command('next')
            gdb.hit(lambda: qemu.command('rmmod main'), r'Breakpoint [\d.]+, .*hello_end')
            assert 'hello_end' in gdb.command('bt')
        # The next continue completes the second unload before failure/lab checks.
        gdb.send('continue')
        qemu.command('insmod /mnt/labs/A01/hello_lab.ko fail_init=1; echo FAIL_INIT_RC=$?')
        wait_for(lambda: 'FAIL_INIT_RC=22' in qemu.output or 'FAIL_INIT_RC=1' in qemu.output, 'A01 controlled init failure')
        assert 'fail_init=1' in qemu.output, qemu.output
        qemu.command('insmod /mnt/labs/A01/hello_lab.ko; rmmod hello_lab; echo A01_CLEANUP_PASS')
        wait_for(lambda: re.search(r'(?m)^A01_CLEANUP_PASS\r?$', qemu.output), 'A01 success/cleanup')
        # Exercise a normal module .text breakpoint while it is loaded.
        gdb.proc.send_signal(signal.SIGINT)
        wait_for(lambda: gdb.output.rstrip().endswith('(gdb)'), 'interrupt')
        gdb.command('tbreak a02_wakeup_write')
        gdb.send('continue')
        qemu.command('insmod /mnt/labs/A02/sched_lab.ko; echo wake > /proc/a02_wakeup')
        wait_for(lambda: re.search(r'[Bb]reakpoint [\d.]+, .*a02_wakeup_write', gdb.output), 'normal .text')
        assert 'a02_wakeup_write' in gdb.command('bt')
        assert '= 5' in gdb.command('print count')
        assert 'symbols current for sched_lab' in gdb.command('kernel-lab-refresh')
        gdb.send('continue')
        qemu.command('sleep 1; cat /proc/a02_wakeup; rmmod sched_lab; echo KO_RUNTIME_PASS; poweroff -f')
        wait_for(lambda: 'handled=1' in qemu.output and re.search(r'(?m)^KO_RUNTIME_PASS\r?$', qemu.output), 'normal callback and cleanup')
        qemu.proc.wait(timeout=30)
        assert qemu.proc.returncode == 0
        assert 'module symbol error' not in gdb.output
        assert 'Traceback' not in gdb.output
        print('CLI_KO_DEBUG=PASS', flush=True)
    finally:
        if gdb:
            gdb.close()
        qemu.close()


def dap(kernel, port, adapter, output):
    qemu = Qemu(kernel, port, output / 'dap-qemu.log')
    client = Dap(adapter, output / 'cppdbg.log')
    try:
        client.request('initialize', {'adapterID': 'cppdbg', 'linesStartAt1': True,
                                      'columnsStartAt1': True, 'pathFormat': 'path'})
        config = json.loads((kernel / '.vscode/launch.json').read_text())['configurations'][0]
        config.pop('preLaunchTask', None)  # QEMU above uses the same startup script.
        config = json.loads(json.dumps(config).replace('${workspaceFolder}', str(kernel)))
        config['miDebuggerServerAddress'] = 'localhost:' + str(port)
        config['logging'] = {'engineLogging': True}
        launch = client.send('launch', config)
        client.receive(lambda m: m.get('event') == 'initialized')
        source = REPO / 'customized/main.c'
        lines = source.read_text().splitlines()
        init_line = next(i for i, line in enumerate(lines, 1) if 'printk(KERN_INFO "Loading' in line)
        exit_line = next(i for i, line in enumerate(lines, 1) if 'printk(KERN_INFO "Goodbye' in line)
        client.request('setBreakpoints', {'source': {'path': str(source)},
                                         'breakpoints': [{'line': init_line}, {'line': exit_line}]})
        client.request('configurationDone')
        client.response(launch)
        boot = client.stopped()
        stack = client.request('stackTrace', {'threadId': boot['threadId']})['stackFrames']
        assert stack, stack
        client.request('continue', {'threadId': boot['threadId']})
        qemu.ready()
        for expected in (init_line, exit_line, init_line, exit_line):
            qemu.command('insmod /mnt/customized/main.ko' if expected == init_line else 'rmmod main')
            stop = client.stopped()
            assert stop['reason'] == 'breakpoint', stop
            frames = client.request('stackTrace', {'threadId': stop['threadId']})['stackFrames']
            frame = frames[0]
            assert pathlib.Path(frame['source']['path']).resolve() == source, frame
            assert frame['line'] == expected, frame
            result = client.request('evaluate', {'expression': '(unsigned long)$pc',
                                                 'frameId': frame['id'], 'context': 'watch'})
            assert result.get('result'), result
            if expected == init_line:
                client.request('next', {'threadId': stop['threadId']})
                step = client.stopped()
                assert step['reason'] == 'step', step
            client.request('continue', {'threadId': stop['threadId']})
        qemu.command('echo CPPDBG_KO_PASS; poweroff -f')
        wait_for(lambda: re.search(r'(?m)^CPPDBG_KO_PASS\r?$', qemu.output), 'cppdbg cleanup')
        qemu.proc.wait(timeout=30)
        assert qemu.proc.returncode == 0
        print('VSCODE_CPPDBG_KO_DEBUG=PASS', flush=True)
    finally:
        client.close()
        qemu.close()


def smoke(kernel, port, output):
    qemu = Qemu(kernel, port, output / 'direct-qemu.log', wait_gdb=False)
    try:
        qemu.ready()
        qemu.command('echo DIRECT_QEMU_PASS; exit')
        qemu.proc.wait(timeout=30)
        assert qemu.proc.returncode == 0
        wait_for(lambda: re.search(r'(?m)^DIRECT_QEMU_PASS\r?$', qemu.output), 'direct boot')
        assert 'Guest Shell 已退出' in qemu.output
        print('DIRECT_QEMU_BOOT_EXIT=PASS', flush=True)
    finally:
        qemu.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kernel', type=pathlib.Path, required=True)
    parser.add_argument('--adapter', type=pathlib.Path, required=True)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    parser.add_argument('--port', type=int, default=12345)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    cli(args.kernel, args.kernel / '.vscode/kernel-lab.gdb', args.port, args.output)
    dap(args.kernel, args.port + 1, args.adapter, args.output)
    smoke(args.kernel, args.port + 2, args.output)
    print('KO_DEBUG_VALIDATION=PASS', flush=True)


if __name__ == '__main__':
    main()
