// Copyright 2016 The Bazel Authors. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include "src/main/cpp/workspace_layout.h"

#include <assert.h>

#include "src/main/cpp/blaze_util_platform.h"
#include "src/main/cpp/util/file.h"
#include "src/main/cpp/util/file_platform.h"
#include "src/main/cpp/util/path.h"

namespace blaze {

using std::string;
using std::vector;

static const char kWorkspaceMarker[] = "WORKSPACE";

blaze_util::Path WorkspaceLayout::GetOutputRoot() const {
  return blaze::GetOutputRoot();
}

bool WorkspaceLayout::InWorkspace(const blaze_util::Path& workspace) const {
  return workspace.Join(kWorkspaceMarker).Exists();
}

blaze_util::Path WorkspaceLayout::GetWorkspace(const blaze_util::Path& cwd) const {
  assert(!cwd.Empty());
  blaze_util::Path workspace = cwd;

  do {
    if (InWorkspace(workspace)) {
      return workspace;
    }
    workspace = workspace.Dirname();
  } while (!workspace.Empty() && !workspace.IsRootDirectory());
  return blaze_util::Path();
}

string WorkspaceLayout::GetPrettyWorkspaceName(
    const blaze_util::Path& workspace) const {
  // e.g. A Bazel server process running in ~/src/myproject (where there's a
  // ~/src/myproject/WORKSPACE file) will appear in ps(1) as "bazel(myproject)".
  return workspace.Basename();
}

std::string WorkspaceLayout::GetWorkspaceRcPath(
    const std::string &workspace,
    const std::vector<std::string> &startup_args) const {
  // TODO(b/36168162): Rename and remove the tools/ prefix. See
  // https://github.com/bazelbuild/bazel/issues/4502#issuecomment-372697374
  // for the final set of bazelrcs we want to have.
  return blaze_util::JoinPath(workspace, "tools/bazel.rc");
}

bool WorkspaceLayout::WorkspaceRelativizeRcFilePath(const string &workspace,
                                                    string *path_fragment)
    const {
  // Strip off the "%workspace%/" prefix and prepend the true workspace path.
  // In theory this could use alternate search paths for blazerc files.
  path_fragment->assign(
      blaze_util::JoinPath(workspace,
                           path_fragment->substr(WorkspacePrefixLength)));
  return true;
}

}  // namespace blaze
