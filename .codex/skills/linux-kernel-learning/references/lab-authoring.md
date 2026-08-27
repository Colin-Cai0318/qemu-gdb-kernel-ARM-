# Lab authoring checklist

Each `labs/Axx` lab should contain:

- `README.md`: objectives, prerequisites, theory questions, source symbols, build/run steps, dynamic observation, cleanup, failure path, and acceptance evidence.
- one focused C module or reproducer with SPDX identifier and bounded parameters;
- a Kbuild Makefile using `KDIR`, `ARCH=arm64`, and `CROSS_COMPILE=aarch64-linux-gnu-` defaults;
- clean unload/error unwinding that prevents callbacks or threads from using freed module code;
- no generated objects or private environment data.

Validate in order:

1. static repository checks;
2. external module build with the declared kernel tree;
3. `file` and `modinfo`/`vermagic` checks;
4. guest load, normal operation, and unload;
5. failure/cleanup path;
6. GDB, ftrace, tracepoint, or log evidence tied back to source;
7. post-test confirmation that the module is unloaded and tracing/settings are restored.
