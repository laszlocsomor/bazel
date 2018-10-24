# Copyright 2018 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import unittest

from src.test.py.bazel import test_base


class MapruleTest(test_base.TestBase):

  def _FailWithOutput(self, output):
    self.fail('FAIL:\n | %s\n---' % '\n | '.join(output))

  def _AssertBuilds(self, target):
    exit_code, stdout, stderr = self.RunBazel(['build', target])
    if exit_code != 0:
      self._FailWithOutput(stdout + stderr)

#  def _AssertPasses(self, target):
#    exit_code, stdout, stderr = self.RunBazel(
#        ['test', target, '--test_output=errors'])
#    if exit_code != 0:
#      self._FailWithOutput(stdout + stderr)
#
#  def _AssertFails(self, target):
#    exit_code, stdout, stderr = self.RunBazel(['test', target])
#    if exit_code == 0:
#      self._FailWithOutput(stdout + stderr)

  def testSimpleRuleWithForeachSrcsFromMultiplePackages(self):
    """Assert that outputs are generated for all files in foreach_srcs."""
    self.ScratchFile('WORKSPACE')
    self.CopyFile(
        self.Rlocation('io_bazel/tools/build_rules/maprule.bzl'),
        'foo/maprule.bzl')
    self.ScratchFile('foo/BUILD', [
        'load(":maprule.bzl", "maprule")',
        '',
        'filegroup(',
        '    name = "files",',
        '    srcs = ["a.txt", "//bar:files"],',
        ')',
        '',
        'maprule(',
        '    name = "x",',
        '    outs = {"wc": "{src_name}_wc.txt"},',
        '    cmd = "wc -c \$(src) > \$(wc)",',
        '    foreach_srcs = [":files"],',
        ')',
    ])
    self.ScratchFile('bar/BUILD', [
        'filegroup(',
        '    name = "files",',
        '    srcs = ["b.txt"],',
        '    visibility = ["//visibility:public"],',
        ')'])
    self.ScratchFile('foo/a.txt', ['hello', 'world'])
    self.ScratchFile('bar/b.txt', ['Hallo', 'Welt'])

    self._AssertBuilds('//foo:x')


#  cat >$pkg/sub/BUILD <<EOF
#filegroup(
#    name = "files",
#    srcs = ["b.txt"],
#    visibility = ["//visibility:public"],
#)
#EOF
#
#  echo -n "hello" > "$pkg/a.txt"
#  echo -n "my darling" > "$pkg/sub/b.txt"
#
#  blaze build "//$pkg:x" || fail "build failed"
#  [ -e "blaze-genfiles/$pkg/x.outputs/$pkg/a.txt_wc.txt" ] || fail "output missing"
#  [ -e "blaze-genfiles/$pkg/x.outputs/$pkg/sub/b.txt_wc.txt" ] || fail "output missing"
#  assert_equals 5 $(cat blaze-genfiles/$pkg/x.outputs/$pkg/a.txt_wc.txt)
#  assert_equals 10 $(cat blaze-genfiles/$pkg/x.outputs/$pkg/sub/b.txt_wc.txt)
#}


if __name__ == '__main__':
  unittest.main()
