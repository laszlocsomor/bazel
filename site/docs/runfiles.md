---
layout: documentation
title: Runfiles
---

# Runfiles

Runfiles are run-time file dependencies of a rule, typically of a binary- or
test rule. Also known as "data-dependencies", they are frequently used for
telling Bazel what files a binary needs while running, such as configuration
files, static assets, generated assets, or input files to process. Runfiles
are always read-only.

Bazel creates symlinks in the output directory during the build, pointing to
the actual files. When you run the binary it can read the files through the
symlinks.

You need to declare all runfiles that a binary needs, otherwise Bazel won't
know about them, and won't stage them in sandboxes and remote executors.

## Example

Our program `//src/main/java/com/example:main` needs its configuration file
`//config:flags.txt` at runtime.

(This example works on Linux with sandboxing. Some things are different on
other platforms and other execution modes. More about that later.)

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

`src/main/java/com/example/Main.java`:

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

To build a rule that has runfiles, Bazel first writes a text file that lists
the symlink names and targets -- the _runfiles manifest_. Bazel then creates
a directory tree with those symlinks -- the _runfiles tree_ or
_symlink tree_.

### Runfiles tree

The _runfiles tree_ is a tree of symlinks that point to the actual runfiles.

The tree's root directory is the _runfiles root_. Its name is always
`<rule_name>.runfiles/` and it's usually (see below for clarification) under
`bazel-bin/<package-name>/` next to the rule's main output. In our previous
example the runfiles root of `//src/main/java/com/example:main` is
`bazel-bin/src/main/java/com/example/main.runfiles/`.

For each workspace that the binary has runfiles from, the runfiles root has a
subdirectory. The main workspace is called "runfiles_example1", so there's a
directory for that. The `java_binary` rule implicitly data-depends on files
in the `@local_jdk` workspace, so there's also a directory for that.

Under those directories are the symlinks. Each symlink's path corresponds to
the file it points to. For source files it's the same as the
workspace-relative path of the file. For generated files it's the same as the
`bazel-out/<config-hash>/`-relative path, without the `bazel-out/.../` part.

#### Where is the runfiles tree

The runfiles tree is usually next to the binary. That was the case in our example.

But you can disable building a runfiles tree with `--noenable_runfiles`. This
makes sense when a runfiles tree is large and building it takes long. Bazel
will create an empty runfiles tree in this case: just the runfiles root
directory and a `MANIFEST` file in it.

Another case is when the binary ("inner") is the runfile of another binary
("outer"). In this case Bazel merges the inner binary's runfiles tree with
the outermost binary's, as if all runfiles were declared for the outermost
binary. (Bazel does this to avoid duplicate work: if the two binaries share
most of the same runfiles, then building a common runfiles tree is more
efficient than building a tree for each.)

### Runfiles manifest

The _runfiles manifest_ is a text file that describes the layout of the
_runfiles tree_.

It is encoded as ISO 8859-1, and each line contains two paths: a relative
symlink path (the _runfile path_) and an absolute path that is the symlink's
target, i.e. the actual runfile. The paths are separated by space.

#### Where is the runfiles manifest

Like the runfiles tree, the runfiles manifest is typically next to the
binary. It has two copies, one next to the runfiles root called
`<rule_name>.runfiles_manifest`, and one under the runfiles root called
`MANIFEST`.

You can disable building a runfiles manifest with
`--noenable_runfile_manifests`. Note that this also disables building a
runfiles tree: not even a runfiles root directory will be created.

And again, if a binary is a runfile of another binary, then Bazel creates no
runfiles manifest for it, instead the content is merged into the outermost
binary's runfiles manifest.

## Accessing runfiles

### Runfile paths

The _runfile path_ is the relative path of a runfile symlink under the
runfiles root.

In our previous example the runfile path of
`@runfiles_example1//config:flags.txt` is
`runfiles_example1/config/flags.txt`. As this example suggests, you can
derive this path from the target's label:
`<workspace name>/<package path>/<target name>`. You refer to a runfile by
its runfile path.

To access a runfile, the binary also needs to know where's the runfiles root.
If it doesn't know or if the user disabled generating a runfiles tree, then
the binary needs to know where's the runfiles manifest and look up the path
in that. If the user disabled both, then the binary cannot use its runfiles.

### `bazel test`

When you `bazel test` a test target, Bazel sets the working directory to the
runfiles root.

Bazel also exports this path as the `RUNFILES_DIR` environment variable, and
the runfiles manifest's path as `RUNFILES_MANIFEST_FILE`.

You can access runfiles by their runfile path, relative to the current
directory or to `${RUNFILES_DIR}`, or you can look up their path in the
`${RUNFILES_MANIFEST_FILE}`.

Note that if you disable building the runfiles tree and/or the runfiles
manifest, then Bazel won't export these variables.

### `bazel run`

If you `bazel run` a target then Bazel sets its working directory to the
runfiles root. However, Bazel doesn't export the RUNFILES_\* environment
variables.

### Direct execution from `bazel-bin/`

If you build a target and run it from `bazel-bin/`, then its working
directory will be the current directory from the terminal. The program needs
to find its runfiles root on its own.

The program in this case may mean a _launcher_ or the actual binary.

#### Launchers

For some rule types Bazel builds a _launcher_. For example the main output of
a `java_binary` is a Bash script (on Linux, macOS) or `.exe` file (on
Windows) whose job is to set up the environment, compute the classpath, and
launch the JVM.

For some rule types Bazel builds a launcher on one platform but not on
others. For example `sh_binary` has no launcher on Linux and macOS; its main
output is a symlink to the main script file. But on Windows it creates a
`.exe` file whose job is to find the Bash binary and run the main shell
script with it.

Finally, for some rule types Bazel builds no launcher at all. For example
`cc_binary` targets' output is just the binary.

#### Runfiles discovery

If there's a launcher, it can try to find the runfiles root and export its
path as an environment variable and/or set it as the working directory.

If there's no launcher, then the main program needs to do the same. If the
runfiles tree is next to the binary, it's enough to know
`argv[0]`. But when the binary is a runfile of another binary, then it's the
outer binary's responsibility to tell the inner binary where the runfiles
are.

How the two binaries communicate this is up to them. Typically the outer
binary exports the `RUNFILES_DIR` and/or `RUNFILES_MANIFEST_FILE` environment
variables, and the inner binary picks those up.

## TODO

Runfiles libraries: are meant to hide this complexity and different launch schenarios.

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