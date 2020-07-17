---
layout: documentation
title: Runfiles
---

# Runfiles

Runfiles are run-time file dependencies of a rule, typically of a binary- or
test rule. Also known as "data-dependencies", they are frequently used to
tell Bazel about files a binary needs while running, such as configuration
files, static assets, generated assets, or input files to operate on.
Runfiles are always read-only.

During the build, Bazel creates symlinks in the output directory that point
to the actual files. When executed, the binary can access the files via these
symlinks. You should declare all runfiles that a binary needs, otherwise
Bazel won't know about them and won't stage them in sandboxes and remote
executors.

## Example

Our program `//src/main/java/com/example:main` needs its configuration file
`//config:flags.txt` at runtime.

(This example works on Linux with sandboxing. Some things are different on
other platforms and other execution modes. More about that below.)

### Input files

Workspace layout:
```
.
├── config
│   ├── BUILD
│   └── flags.txt
├── src
│   └── main
│       └── java
│           └── com
│               └── example
│                   ├── BUILD
│                   └── Main.java
└── WORKSPACE
```

`WORKSPACE`:
```
workspace(name = "runfiles_example1")
```

`config/BUILD`:

```
filegroup(
    name = "flags",
    srcs = ["flags.txt"],
    visibility = ["//visibility:public"],
)
```

`config/flags.txt`:

```
--foo=1
--bar=hello
```

`src/main/java/com/example/BUILD`:

```python
java_binary(
    name = "main",
    srcs = ["Main.java"],
    main_class = "com.example.Main",
    data = ["//config:flags"],
)
```

`cat src/main/java/com/example/Main.java`:

```java
package com.example;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Paths;

public class Main {
  public static void main(String[] args) throws IOException {
    System.out.println("Config file contents:");
    String path = System.getenv("JAVA_RUNFILES") + "/runfiles_example1/config/flags.txt";
    for (String line : Files.readAllLines(Paths.get(path))) {
      System.out.println(line);
    }
  }
}
```

### Output

Build the rule:

```bash
  $ bazel --ignore_all_rc_files build //src/main/java/com/example:main
(...)
INFO: Build completed successfully, 1 total action
```

(With `--ignore_all_rc_files` Bazel won't use your RC files, so this example
behaves predictably.)

List the runfiles tree (the symlinks):

```bash
  $ find bazel-bin/src/main/java/com/example/main.runfiles
bazel-bin/src/main/java/com/example/main.runfiles
bazel-bin/src/main/java/com/example/main.runfiles/MANIFEST
bazel-bin/src/main/java/com/example/main.runfiles/local_jdk
bazel-bin/src/main/java/com/example/main.runfiles/local_jdk/bin
bazel-bin/src/main/java/com/example/main.runfiles/local_jdk/bin/javadoc
bazel-bin/src/main/java/com/example/main.runfiles/local_jdk/bin/jimage
(...)
bazel-bin/src/main/java/com/example/main.runfiles/runfiles_example1/external/local_jdk/lib/libsaproc.so
bazel-bin/src/main/java/com/example/main.runfiles/runfiles_example1/config
bazel-bin/src/main/java/com/example/main.runfiles/runfiles_example1/config/flags.txt
bazel-bin/src/main/java/com/example/main.runfiles/runfiles_example1/src
bazel-bin/src/main/java/com/example/main.runfiles/runfiles_example1/src/main
bazel-bin/src/main/java/com/example/main.runfiles/runfiles_example1/src/main/java
bazel-bin/src/main/java/com/example/main.runfiles/runfiles_example1/src/main/java/com
bazel-bin/src/main/java/com/example/main.runfiles/runfiles_example1/src/main/java/com/example
bazel-bin/src/main/java/com/example/main.runfiles/runfiles_example1/src/main/java/com/example/main.jar
bazel-bin/src/main/java/com/example/main.runfiles/runfiles_example1/src/main/java/com/example/main
```

That's more than you might expect. We'll explain that later.

See that
`bazel-bin/src/main/java/com/example/main.runfiles/runfiles_example1/config/flags.txt`
is a symlink that points into the workspace:

```bash
  $ readlink bazel-bin/src/main/java/com/example/main.runfiles/runfiles_example1/config/flags.txt 
/tmp/rf/ex1/config/flags.txt

  $ pwd
/tmp/rf/ex1
```

Output on Ubuntu 20.04 with Bazel 3.4.1:

```bash
  $ bazel --ignore_all_rc_files run //src/main/java/com/example:main
(...)
INFO: Build completed successfully, 1 total action
Config file contents:
--foo=1
--bar=hello
```

## Under the hood

When building a rule with runfiles, Bazel first writes a file that lists the
symlink names and targets -- this is the "Runfiles manifest". Then Bazel
creates a directory tree with those symlinks -- the "Runfiles directory",
"Runfiles tree", or "Symlink tree". The root of the directory tree is called
the "Runfiles root".

### Runfiles tree

The runfiles tree is rooted at the runfiles root: the `<rule_name>.runfiles/`
directory under `bazel-bin/`. In our example above, the runfiles root of
`//src/main/java/com/example:main` is
`bazel-bin/src/main/java/com/example/main.runfiles`.

The runfiles root has subdirectories for each workspace where the binary's
runfiles originate. The main workspace is called "runfiles_example1", so
there's a directory for that. The `java_binary` implicitly data-depends on
files in the `@local_jdk` workspace, so there's also a directory for that.

Under those directories are the symlinks. Each symlink's path corresponds to
the file it points to. For source files it's the same as the
workspace-relative path of the file. For generated files it's the same as the
`bazel-out/<config-hash>/`-relative path, without the `bazel-out/.../` part.

### Runfiles manifest

The runfiles manifest is a text file. It has two copies, one next to the
runfiles root called `<rule_name>.runfiles_manifest`, and one under the
runfiles root called `MANIFEST`.

This file descibes the layout of the runfiles tree. Each line contains two
paths separated by space: a relative symlink path (called the "runfiles
path") and an absolute symlink target path.

<hr>

(_More documentation to come, follow <https://github.com/bazelbuild/bazel/issues/10022>_.)

<!--

How to access runfiles when binary runs as part of a build action, with bazel
run/test, or ran directly. Platform differences, handling space, sandboxing
and remote execution.

And:
- When invoked directly.
- When invoked indirectly as a data-dependency of another executable.

And:
- On Linux/Mac (symlink tree and manifest)
- On Windows (manifest)
- With sandboxing (symlink tree)

Documentation should include:

- The generic resolution algorithm
- Instructions for using language-specific libraries implementing the algorithm
- Ideally some brief explanation/motivation why this is so dang hard

Any target can be a data-dependency, files; filegroups; file-providing rules (e.g. genrule);


- why runfiles are readonly, what to do if you need write access
- why we need runfiles
- why are there more files there than expected
- tree layout (see also: --[no]legacy_external_runfiles)
- runfiles of libs, and why
- symlinks point into the workspace or output dir
- manifest vs dir tree
- dfferences: platforms vs exec methods (manifest-only, tree-only)
- ext.repos
- runfiles declared in rules in ext.repos, runfile paths?
- __main__ / ws name
- envvars with bazel run, bazel test, naked run
- runfiles roll-up from deps, and why
- aside: genrule and its srcs, why it has bazel-out/<cfg>/, why runfiles don't
- windows
- remote exec
- runfiles libraries, rlocation
- manifest file encoding
- spaces (see --[no]build_runfile_manifests)
- all runfiles-related flags explained 
- $(location <runfile>) in `args` attribute, and caveat on Windows
- java doesn't have RUNFILES_DIR, just JAVA_RUNFILES

You declare a rule's runfiles in its `data` attribute. Bazel

Most rules support the `data` attribute, not just binary rules. Rules
typically inherit the runfiles of all their dependencies, which is useful to
know when writing a library rule: if a binary that depends on this library
will need supporting runfiles to use the library, then declare the runfiles
on the library. This works even if the library is a transitive, not direct,
dependency of the binary.
-->