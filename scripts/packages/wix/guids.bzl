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

# Release GUIDs for the .msi installer of Bazel.
#
# Every Bazel release with a .msi installer must have its entry in this file,
# and each version's GUID must be different.
#
# Once a version has an assigned a GUID do not remove it and do not change it.
# Otherwise we won't be able to reproducibly build Bazel installers.
#
# If you need new GUIDs, simply generate them on Linux using /usr/bin/uuidgen
# You may pre-populate this dictionary with GUIDs for future Bazel versions.
_bazel_msi_guid = {
    "0.19.0": "edab783c-b8f3-4991-b180-495b73e8ed0d",
    "0.20.0": "f4748128-1098-4242-a06a-da925aaf8d75",

    # 0.99.0 is used for testing only
    "0.99.0": "575f6e77-1879-47d7-8db4-26201920e11e",
}

def get_guid(version):
  """Returns the .msi installer GUID of a given Bazel version.

  version: string; must be a key in _bazel_msi_guid

  Return:
    string; the GUID of the requested Bazel release version
  """
  result = _bazel_msi_guid.get(version)
  if not result:
    fail("Could not find release GUID for version %s, please update guids.bzl" % version)
  reverse_dict = dict()
  for version, guid in _bazel_msi_guid.items():
    other_version = reverse_dict.get(guid)
    if other_version:
      fail("Duplicate GUID for versions %s and %s, please fix guids.bzl" % (version, other_version))
    reverse_dict[guid] = version
  return result
