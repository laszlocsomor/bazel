licenses(["notice"])  # Apache 2.0

filegroup(
    name = "srcs",
    srcs = glob(["**"]),
    visibility = ["//tools:__pkg__"],
)

filegroup(
    name = "embedded_tools_srcs",
    srcs = [
        "BUILD.tools",
        "test_rules.bzl",
    ],
    visibility = ["//visibility:public"],
)

py_test(
    name = "test_rules_test",
    srcs = ["test_rules_test.py"],
    data = ["test_rules.bzl"],
    deps = ["//src/test/py/bazel:test_base"],
)

py_test(
    name = "maprule_test",
    srcs = ["maprule_test.py"],
    data = ["maprule.bzl"],
    deps = ["//src/test/py/bazel:test_base"],
)

load("//tools/build_rules:maprule.bzl", "maprule")

filegroup(
    name = "source_files",
    srcs = ["dummy2.txt", "dummy3.txt"],
)

maprule(
    name = "dummy",
    srcs = ["dummy1.txt"],
    outs = {
        "out1": "{default}.out1",
        "out2": "out2/{src_name_noext}.out2",
    },
    cmd = " && ".join([
        "cat $(location dummy1.txt) $(src) > $(out1)",
        "cat $(SRCS) $(src) > $(out2)",
    ]),
    foreach_srcs = [":source_files"],
    # language = "bash",
)
