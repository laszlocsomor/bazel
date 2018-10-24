#!/bin/bash
#
# Integration tests for the maprule() skylark rule.
# See //tools/build_rules/maprule.bzl

[ -z "$TEST_SRCDIR" ] && { echo "TEST_SRCDIR not set!" >&2; exit 1; }
source $TEST_SRCDIR/google3/devtools/blaze/integration/unittest.bash || exit 1
source $TEST_SRCDIR/google3/devtools/blaze/integration/create_mock_client.sh || exit 1

create_and_cd_client
put_blaze_on_path
write_default_blazerc

mkdir maprule
touch maprule/BUILD
ln -s $TEST_SRCDIR/google3/tools/build_rules/maprule.bzl \
    maprule/maprule.bzl

# Tests that outputs are generated for all files in maprule.foreach_srcs and
# that these outputs are under the expected paths and have the expected
# contents.
function test_simple_rule_with_foreach_srcs_from_multiple_packages() {
  local -r pkg=${FUNCNAME[0]}
  mkdir -p "$pkg/sub" || fail "mkdir $pkg/sub"

  cat >$pkg/BUILD <<EOF
load("//maprule:maprule.bzl", "maprule")

filegroup(
    name = "files",
    srcs = [
        "a.txt",
        "//$pkg/sub:files",
    ],
)

maprule(
    name = "x",
    outs = {"wc": "{src}_wc.txt"},
    cmd = "wc -c \$(src) > \$(wc)",
    foreach_srcs = [":files"],
)
EOF

  cat >$pkg/sub/BUILD <<EOF
filegroup(
    name = "files",
    srcs = ["b.txt"],
    visibility = ["//visibility:public"],
)
EOF

  echo -n "hello" > "$pkg/a.txt"
  echo -n "my darling" > "$pkg/sub/b.txt"

  blaze build "//$pkg:x" || fail "build failed"
  [ -e "blaze-genfiles/$pkg/x.outputs/$pkg/a.txt_wc.txt" ] || fail "output missing"
  [ -e "blaze-genfiles/$pkg/x.outputs/$pkg/sub/b.txt_wc.txt" ] || fail "output missing"
  assert_equals 5 $(cat blaze-genfiles/$pkg/x.outputs/$pkg/a.txt_wc.txt)
  assert_equals 10 $(cat blaze-genfiles/$pkg/x.outputs/$pkg/sub/b.txt_wc.txt)
}

# Tests that files in maprule.srcs are available to all per-foreach_srcs action.
function test_using_constant_srcs() {
  local -r pkg=${FUNCNAME[0]}
  mkdir "$pkg" || fail "mkdir $pkg"
  cat >$pkg/BUILD <<'EOF'
load("//maprule:maprule.bzl", "maprule")

maprule(
    name = "x",
    srcs = ["extra.txt"],
    outs = {"out": "{src}.out"},
    cmd = "cat $(location extra.txt) $(src) | tr '\n' ' ' > $(out)",
    foreach_srcs = [
        "a.txt",
        "b.txt",
    ],
)
EOF
  echo "prefix" > $pkg/extra.txt
  echo "hello" > $pkg/a.txt
  echo "world" > $pkg/b.txt

  blaze build //$pkg:x || fail "build failed"
  [ -e "blaze-genfiles/$pkg/x.outputs/$pkg/a.txt.out" ] || fail "output missing"
  [ -e "blaze-genfiles/$pkg/x.outputs/$pkg/b.txt.out" ] || fail "output missing"
  cat blaze-genfiles/$pkg/x.outputs/$pkg/a.txt.out | grep -sq "prefix hello" || fail "bad output"
  cat blaze-genfiles/$pkg/x.outputs/$pkg/b.txt.out | grep -sq "prefix world" || fail "bad output"
}

# Tests that multiple outputs can be created.
function test_multiple_outputs() {
  local -r pkg=${FUNCNAME[0]}
  mkdir "$pkg" || fail "mkdir $pkg"

  cat >$pkg/BUILD <<'EOF'
load("//maprule:maprule.bzl", "maprule")

maprule(
    name = "x",
    outs = {
        "a": "{src}.a",
        "b": "{src}.b",
    },
    cmd = "cat $(src) | tr 'l' 'A' > $(a); cat $(src) | tr 'l' 'B' > $(b)",
    foreach_srcs = [
        "a.txt",
        "b.txt",
    ],
)
EOF

  echo -n "hello" > $pkg/a.txt
  echo -n "world" > $pkg/b.txt

  blaze build //$pkg:x || fail "build failed"
  [ -e "blaze-genfiles/$pkg/x.outputs/$pkg/a.txt.a" ] || fail "output missing"
  [ -e "blaze-genfiles/$pkg/x.outputs/$pkg/b.txt.a" ] || fail "output missing"
  [ -e "blaze-genfiles/$pkg/x.outputs/$pkg/a.txt.b" ] || fail "output missing"
  [ -e "blaze-genfiles/$pkg/x.outputs/$pkg/b.txt.b" ] || fail "output missing"
  assert_equals "heAAo" $(cat blaze-genfiles/$pkg/x.outputs/$pkg/a.txt.a)
  assert_equals "worAd" $(cat blaze-genfiles/$pkg/x.outputs/$pkg/b.txt.a)
  assert_equals "heBBo" $(cat blaze-genfiles/$pkg/x.outputs/$pkg/a.txt.b)
  assert_equals "worBd" $(cat blaze-genfiles/$pkg/x.outputs/$pkg/b.txt.b)
}

# Tests that the Make Variable $(@) works iff there is only one output template.
function test_single_output_makevar() {
  local -r pkg=${FUNCNAME[0]}
  mkdir "$pkg" || fail "mkdir $pkg"

  cat >$pkg/BUILD <<'EOF'
load("//maprule:maprule.bzl", "maprule")

maprule(
    name = "good",
    outs = {"a": "{src}.a"},
    cmd = "cat $(src) > $(@)",
    foreach_srcs = [
        "a.txt",
        "b.txt",
    ],
)

maprule(
    name = "bad",
    outs = {
        "a": "{src}.a",
        "b": "{src}.b",
    },
    cmd = "cat $(src) > $(@)",
    foreach_srcs = [
        "a.txt",
        "b.txt",
    ],
)
EOF

  echo -n "hello" > $pkg/a.txt
  echo -n "world" > $pkg/b.txt

  blaze build //$pkg:good || fail "build failed"
  blaze build //$pkg:bad >&$TEST_log && fail "expected failure"
  expect_log "\$(@) not defined"
}

function test_outs_placeholders() {
  local -r pkg=${FUNCNAME[0]}
  mkdir -p "${pkg}"/{a,b} || fail "mkdir"
  cat >"${pkg}/BUILD" <<EOF
load("//maprule:maprule.bzl", "maprule")

maprule(
    name = "x",
    outs = {
        "a": "aa/{src}.a",
        "b": "bb/{src_dir}.b",
        "c": "cc/{src_name}.c",
        "d": "dd/{src_name_noext}.d",
    },
    cmd = " ; ".join([
        "mkdir -p \$\$(dirname \$(a))",
        "mkdir -p \$\$(dirname \$(b))",
        "mkdir -p \$\$(dirname \$(c))",
        "mkdir -p \$\$(dirname \$(d))",
        "touch \$(a)",
        "touch \$(b)",
        "touch \$(c)",
        "touch \$(d)",
    ]),
    foreach_srcs = [
        "//${pkg}:a/src.txt",
        "//${pkg}/b:gen.txt",
    ],
)
EOF
  touch "${pkg}/a/src.txt"
  cat >"${pkg}/b/BUILD" << 'EOF'
genrule(
    name = "gen",
    outs = ["gen.txt"],
    cmd = "touch $@",
    visibility = ["//visibility:public"],
)
EOF

  blaze build "//${pkg}:x" || fail "build failed"
  # default
  [[ -e "blaze-genfiles/${pkg}/x.outputs/aa/${pkg}/a/src.txt.a" ]] || fail "output missing"
  [[ -e "blaze-genfiles/${pkg}/x.outputs/aa/${pkg}/b/gen.txt.a" ]] || fail "output missing"
  # src_dir
  [[ -e "blaze-genfiles/${pkg}/x.outputs/bb/${pkg}/a/.b" ]] || fail "output missing"
  [[ -e "blaze-genfiles/${pkg}/x.outputs/bb/${pkg}/b/.b" ]] || fail "output missing"
  # src_name
  [[ -e "blaze-genfiles/${pkg}/x.outputs/cc/src.txt.c" ]] || fail "output missing"
  [[ -e "blaze-genfiles/${pkg}/x.outputs/cc/gen.txt.c" ]] || fail "output missing"
  # src_name_noext
  [[ -e "blaze-genfiles/${pkg}/x.outputs/dd/src.d" ]] || fail "output missing"
  [[ -e "blaze-genfiles/${pkg}/x.outputs/dd/gen.d" ]] || fail "output missing"
}

function assert_analysis_ok() {
  local -r rule=$1
  local -r pkg=$2
  echo 'load("//maprule:maprule.bzl", "maprule")' >"$pkg/BUILD"
  echo "$rule" >> "$pkg/BUILD"
  blaze build --nobuild "//$pkg:x" || fail "analysis failed"
}

function assert_analysis_fail() {
  local -r rule=$1
  local -r errormsg=$2
  local -r pkg=$3
  echo 'load("//maprule:maprule.bzl", "maprule")' >"$pkg/BUILD"
  echo "$rule" >> "$pkg/BUILD"
  if blaze build --nobuild "//$pkg:x" >& "$TEST_log"; then
    fail "expected failure"
  fi
  expect_log "$errormsg"
}

function test_foreach_srcs_required() {
  local -r pkg=${FUNCNAME[0]}
  mkdir "$pkg" || fail "mkdir $pkg"
  assert_analysis_fail \
      'maprule(name="x",cmd=":",outs={"x":"\$(src).x"})' \
      "missing value for mandatory attribute 'foreach_srcs'" \
      "$pkg"
}

function test_foreach_srcs_cannot_be_empty() {
  local -r pkg=${FUNCNAME[0]}
  mkdir "$pkg" || fail "mkdir $pkg"
  assert_analysis_fail \
      'maprule(name="x",cmd=":",outs={"x":"\$(src).x"},foreach_srcs=[])' \
      'attribute foreach_srcs: must not be empty' \
      "$pkg"
}

function test_outs_required() {
  local -r pkg=${FUNCNAME[0]}
  mkdir "$pkg" || fail "mkdir $pkg"
  assert_analysis_fail \
      'maprule(name="x",cmd=":",foreach_srcs=["a"])' \
      "missing value for mandatory attribute 'outs'" \
      "$pkg"
}

function test_outs_cannot_be_empty() {
  local -r pkg=${FUNCNAME[0]}
  mkdir "$pkg" || fail "mkdir $pkg"
  assert_analysis_fail \
      'maprule(name="x",cmd=":",foreach_srcs=["a"],outs={})' \
      'attribute outs: must not be empty' \
      "$pkg"
}

function test_output_path_cannot_be_empty() {
  local -r pkg=${FUNCNAME[0]}
  mkdir "$pkg" || fail "mkdir $pkg"
  assert_analysis_fail \
      'maprule(name="x",cmd=":",foreach_srcs=["a"],outs={"a": ""})' \
      "output path should not be empty" "$pkg"
}

function test_duplicate_make_var_src() {
  local -r pkg=${FUNCNAME[0]}
  mkdir "$pkg" || fail "mkdir $pkg"
  assert_analysis_fail \
      'maprule(name="x",cmd=":",foreach_srcs=["a"],outs={"src":"{src}.x"})' \
      'duplicate Make Variable "src"' \
      "$pkg"
}

function test_duplicate_make_var_something_built_in() {
  local -r pkg=${FUNCNAME[0]}
  mkdir "$pkg" || fail "mkdir $pkg"
  assert_analysis_fail \
      'maprule(name="x",cmd=":",foreach_srcs=["a"],outs={"SRCS":"{src}.x"})' \
      'duplicate Make Variable "SRCS"' \
      "$pkg"
}

function test_outs_template_missing_src_placeholder() {
  local -r pkg=${FUNCNAME[0]}
  mkdir "$pkg" || fail "mkdir $pkg"
  assert_analysis_ok \
      'maprule(name="x",cmd=":",foreach_srcs=["a"],outs={"out":"x"})' "$pkg"
}

function test_outs_template_is_mere_placeholder() {
  local -r pkg=${FUNCNAME[0]}
  mkdir "$pkg" || fail "mkdir $pkg"
  assert_analysis_ok \
      'maprule(name="x",cmd=":",foreach_srcs=["a"],outs={"out":"{src}"})' \
      "$pkg"
}

function test_outs_template_is_malformed() {
  local -r pkg=${FUNCNAME[0]}
  mkdir "$pkg" || fail "mkdir $pkg"
  assert_analysis_fail \
      'maprule(name="x",cmd=":",foreach_srcs=["a"],outs={"out":"{default"})' \
      "Found '{' without matching '}'" "$pkg"
}

function test_outs_template_contains_unknown_placeholder() {
  local -r pkg=${FUNCNAME[0]}
  mkdir "$pkg" || fail "mkdir $pkg"
  assert_analysis_fail \
      'maprule(name="x",cmd=":",foreach_srcs=["a"],outs={"out":"{foo}.x"})' \
      "Missing argument 'foo'" "$pkg"
}

function test_duplicate_outs_template_value() {
  local -r pkg=${FUNCNAME[0]}
  mkdir "$pkg" || fail "mkdir $pkg"
  assert_analysis_fail \
      'maprule(name="x",cmd=":",foreach_srcs=["a"],outs={"a":"{src_name}.x","b":"{src_name}.x"})' \
      "output file generated multiple times:" "$pkg"
}

function test_duplicate_output_name_for_same_file() {
  local -r pkg=${FUNCNAME[0]}
  mkdir "$pkg" || fail "mkdir $pkg"
  assert_analysis_fail \
      'maprule(name="x",cmd=":",foreach_srcs=["a.txt"],outs={"a":"{src_name}.a","b":"{src_name_noext}.txt.a"})' \
      "output file generated multiple times:" "$pkg"
}

function test_duplicate_output_name_for_different_files() {
  local -r pkg=${FUNCNAME[0]}
  mkdir -p "$pkg/other" || fail "mkdir -p $pkg/other"
  echo "exports_files(['a'])" > "$pkg/other/BUILD"
  touch "$pkg/a"
  touch "$pkg/other/a"
  assert_analysis_fail \
      "maprule(name='x',cmd=':',foreach_srcs=['a','//$pkg/other:a'],outs={'a':'{src_name}.a'})" \
      "output file generated multiple times:" "$pkg"
}

function test_uplevel_reference_in_output_template() {
  local -r pkg=${FUNCNAME[0]}
  mkdir "$pkg" || fail "mkdir $pkg"
  assert_analysis_fail \
      'maprule(name="x",cmd=":",foreach_srcs=["a"],outs={"a":"../{src_name}.x"})' \
      "output path should not contain uplevel references" "$pkg"
}

function test_absolute_unix_path_in_output_template() {
  local -r pkg=${FUNCNAME[0]}
  mkdir "$pkg" || fail "mkdir $pkg"
  assert_analysis_fail \
      'maprule(name="x",cmd=":",foreach_srcs=["a"],outs={"a":"/{src_name}.x"})' \
      "output path should be relative" "$pkg"
}

function test_absolute_windows_path_in_output_template() {
  local -r pkg=${FUNCNAME[0]}
  mkdir "$pkg" || fail "mkdir $pkg"
  assert_analysis_fail \
      'maprule(name="x",cmd=":",foreach_srcs=["a"],outs={"a":"c:\\{src_name}.x"})' \
      "output path should be relative" "$pkg"
}

function test_drive_relative_windows_path_in_output_template() {
  local -r pkg=${FUNCNAME[0]}
  mkdir "$pkg" || fail "mkdir $pkg"
  assert_analysis_fail \
      'maprule(name="x",cmd=":",foreach_srcs=["a"],outs={"a":"c:{src_name}.x"})' \
      "output path should be relative" "$pkg"
}

function test_driveless_absolute_windows_path_in_output_template() {
  local -r pkg=${FUNCNAME[0]}
  mkdir "$pkg" || fail "mkdir $pkg"
  assert_analysis_fail \
      'maprule(name="x",cmd=":",foreach_srcs=["a"],outs={"a":"\\{src_name}.x"})' \
      "output path should be relative" "$pkg"
}


run_suite "maprule() integration tests"
