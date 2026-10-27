"""Relocate external module sections before init; source from Linux-aware GDB.

Linux 6.12 lx-symbols omits .init.text/.exit.text. This helper deliberately
leaves the downloaded kernel scripts untouched and uses the same sect_attrs
that the kernel exposes in /sys/module/<name>/sections.
"""
import os
import shutil
import subprocess
import tempfile

import gdb
from linux import constants, modules


def quote(value):
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'


class ModuleSymbols(gdb.Command):
    """kernel-lab-symbols DIR...: watch module loads/unloads in these build dirs.

Safe before boot: this installs hooks without reading uninitialized guest RAM.
For an already booted target, also run kernel-lab-refresh while stopped.
Do not enable lx-symbols simultaneously (it owns another module load hook).
"""

    def __init__(self):
        super().__init__('kernel-lab-symbols', gdb.COMMAND_FILES)
        self.paths = []
        self.loaded = {}
        self.hooks = []
        self.debug_dir = tempfile.TemporaryDirectory(prefix='kernel-lab-gdb-')

    def remove(self, name):
        entry = self.loaded.pop(name, None)
        if entry:
            filename, _ = entry
            gdb.execute('remove-symbol-file ' + quote(filename), to_string=True)
            os.unlink(filename)
            gdb.write('kernel-lab: removed symbols for %s\n' % name)

    def load(self, mod):
        name = mod['name'].string()
        candidates = []
        for path in self.paths:
            for root, dirs, files in os.walk(path):
                for filename in files:
                    if filename.endswith('.ko') and filename[:-3].replace('-', '_') == name:
                        candidates.append(os.path.join(root, filename))
        if not candidates:
            gdb.write('kernel-lab: no .ko found for %s in %s\n' % (name, self.paths))
            return
        if len(candidates) != 1:
            raise gdb.GdbError('Ambiguous .ko for %s: %s' % (name, candidates))
        if not mod['sect_attrs']:
            raise gdb.GdbError('Module section addresses unavailable; enable CONFIG_KALLSYMS and CONFIG_SYSFS')
        attrs = mod['sect_attrs'].dereference()
        sections = {}
        for index in range(int(attrs['nsections'])):
            attr = attrs['attrs'][index]
            sections[attr['battr']['attr']['name'].string()] = int(attr['address'])
        sections.setdefault('.text', int(mod['mem'][constants.LX_MOD_TEXT]['base']))
        self.remove(name)
        objcopy = (os.environ.get('OBJCOPY') or shutil.which('aarch64-linux-gnu-objcopy')
                   or shutil.which('objcopy'))
        if not objcopy:
            raise gdb.GdbError('Install ARM64-capable objcopy or set OBJCOPY')
        # ET_REL sections share link-time address zero. On GDB 15.1 a plain
        # add-symbol-file -s updates minimal symbols but can leave DWARF lines
        # at the .text anchor. Give BFD the actual VMAs before it reads DWARF.
        # A unique disposable copy also prevents BFD caching across reloads.
        handle, filename = tempfile.mkstemp(suffix='.ko.debug', dir=self.debug_dir.name)
        os.close(handle)
        command = [objcopy]
        for section, address in sections.items():
            command += ['--change-section-vma', '%s=0x%x' % (section, address)]
        command += [candidates[0], filename]
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode:
            os.unlink(filename)
            raise gdb.GdbError('objcopy failed: ' + result.stderr)
        gdb.execute('add-symbol-file ' + quote(filename) + ' -readnow', to_string=True)
        self.loaded[name] = (filename, int(mod))
        gdb.write('kernel-lab: loaded %s (including init/exit sections)\n' % candidates[0])

    def invoke(self, arg, from_tty):
        paths = [os.path.realpath(os.path.expanduser(p)) for p in gdb.string_to_argv(arg)]
        if not paths or any(not os.path.isdir(p) for p in paths):
            raise gdb.GdbError('Usage: kernel-lab-symbols EXISTING_BUILD_DIR...')
        self.paths = paths
        for hook in self.hooks:
            hook.delete()
        self.hooks = [ModuleHook('do_init_module', self, True),
                      ModuleHook('free_module', self, False)]
        gdb.execute('set breakpoint pending on')
        gdb.write('kernel-lab: watching module build dirs %s\n' % paths)


class ModuleHook(gdb.Breakpoint):
    def __init__(self, function, owner, loading):
        super().__init__(function, internal=True)
        self.silent = True
        self.owner = owner
        self.loading = loading

    def stop(self):
        try:
            mod = gdb.parse_and_eval('mod')
            if self.loading:
                self.owner.load(mod)
            else:
                self.owner.remove(mod['name'].string())
        except (gdb.error, RuntimeError, OSError) as error:
            # Stop visibly: silently resuming could skip the user's init breakpoint.
            gdb.write('kernel-lab: module symbol error: %s\n' % error, gdb.STDERR)
            return True
        return False


class RefreshSymbols(gdb.Command):
    """kernel-lab-refresh: load symbols for modules already present (booted target)."""

    def __init__(self, owner):
        super().__init__('kernel-lab-refresh', gdb.COMMAND_FILES)
        self.owner = owner

    def invoke(self, arg, from_tty):
        if not self.owner.paths:
            raise gdb.GdbError('Run kernel-lab-symbols DIR... first')
        live = list(modules.module_list())
        names = {mod['name'].string() for mod in live}
        for name in list(self.owner.loaded):
            if name not in names:
                self.owner.remove(name)
        for mod in live:
            name = mod['name'].string()
            if self.owner.loaded.get(name, (None, None))[1] != int(mod):
                self.owner.load(mod)
            else:
                gdb.write('kernel-lab: symbols current for %s\n' % name)


kernel_lab_module_symbols = ModuleSymbols()
RefreshSymbols(kernel_lab_module_symbols)
