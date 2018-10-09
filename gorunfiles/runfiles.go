/* Copyright 2018 The Bazel Authors. All rights reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

/*
Runfiles lookup library for Bazel-built Go binaries and tests.

USAGE:
1.  Depend on this runfiles library from your build rule:

      go_binary(
          name = "my_binary",
          ...
          deps = ["@io_bazel_rules_go//go/tools/bazel/runfiles:go_default_library"],
      )

2.  Import the runfiles library.

      import "github.com/bazelbuild/rules_go/go/tools/bazel/runfiles",

3.  Create a Runfiles object and use RLocation to look up runfile paths:

      func main() {
      	r := runfiles.Create()

		// Important:
		//   If this is a test, use runfiles.CreateForTest()

      	if r == nil {
      		panic("could not init runfiles")
      	}
      	path := r.Rlocation("my_workspace/path/to/my/data.txt")
      	if len(path) > 0 {
      		...  // use the file
      	}


     The code above creates a Runfiles object and retrieves a runfile path.

     The runfiles.Create function uses the runfiles manifest and the
     runfiles directory from the RUNFILES_MANIFEST_FILE and RUNFILES_DIR
     environment variables. If not present, the function looks for the
     manifest and directory near os.Argv[0], the path of the main program.

To start child processes that also need runfiles, you need to set the right
environment variables for them:

  TODO
  std::unique_ptr<Runfiles> runfiles(Runfiles::Create(argv[0], &error));

  std::string path = runfiles->Rlocation("path/to/binary"));
  if (!path.empty()) {
    ... // create "args" argument vector for execv
    const auto envvars = runfiles->EnvVars();
    pid_t child = fork();
    if (child) {
      int status;
      waitpid(child, &status, 0);
    } else {
      for (const auto i : envvars) {
        setenv(i.first.c_str(), i.second.c_str(), 1);
      }
      execv(args[0], args);
    }
*/
package runfiles

import (
	"bufio"
	"io/ioutil"
	"os"
	"path"
	"strings"
)

type Runfiles interface {
	Rlocation(string) string
	Envvars() map[string]string
}

func Create() *_RunfilesImpl {
	return CreateFrom(
		os.Args[0], os.Getenv("RUNFILES_MANIFEST_FILE"),
		os.Getenv("RUNFILES_DIR"))
}

func CreateForTest() *_RunfilesImpl {
	return CreateFrom(
		os.Args[0], os.Getenv("RUNFILES_MANIFEST_FILE"),
		os.Getenv("TEST_SRCDIR"))
}


func CreateFrom(argv0 string, env_mf string, env_dir string) *_RunfilesImpl {
	env_mf, env_dir = discoverPaths(
		argv0, env_mf, env_dir, defaultIsManifest, defaultIsDirectory)
	if len(env_mf) == 0 && len(env_dir) == 0 {
		return nil
	}
	var env_map = map[string]string {
		 "RUNFILES_MANIFEST_FILE": env_mf,
		 "RUNFILES_DIR": env_dir,
		 // TODO(laszlocsomor): remove JAVA_RUNFILES once the Java launcher can
		 // pick up RUNFILES_DIR.
		 "JAVA_RUNFILES": env_dir,
	}

	return &_RunfilesImpl{dir: env_dir, mf: readManifest(env_mf), env: env_map}
}

type _RunfilesImpl struct {
	dir	string
	mf	map[string]string
	env	map[string]string
}

func readManifest(mf string) map[string]string {
	if len(mf) == 0 {
		return nil
	}
	f, err := os.Open(mf)
	if err != nil {
		panic("could not open file")
	}
	defer f.Close()
	dat, err := ioutil.ReadAll(f)
	if err != nil {
		panic("could not read file")
	}
	result := make(map[string]string)
	offs := 0
	for {
		adv, tkn, err := bufio.ScanLines(dat[offs:], true)
		if err != nil {
			panic("failed to read file")
		}
		if adv == 0 {
			break
		}
		offs += adv
		if tokens := strings.SplitN(string(tkn), " ", 2); len(tokens) == 2 {
			result[tokens[0]] = tokens[1]
		} else {
			result[tokens[0]] = ""
		}
	}
	return result
}

func (r *_RunfilesImpl) Rlocation(rpath string) string {
	if len(rpath) == 0 {
		panic("foo")
	}
	if strings.HasPrefix(rpath, "../") ||
		strings.Contains(rpath, "/..") ||
		strings.HasPrefix(rpath, "./") ||
		strings.Contains(rpath, "/./") ||
		strings.HasSuffix(rpath, "/.") ||
		strings.Contains(rpath, "//") {
		panic("bar")
	}

	if path.IsAbs(rpath) {
		return rpath
	}
	if len(r.mf) > 0 {
		return r.mf[rpath]
	} else {
		return path.Join(r.dir, rpath)
	}
}

func (r *_RunfilesImpl) Envvars() map[string]string {
	if r == nil || r.env == nil {
		return nil
	} else {
		result := make(map[string]string)
		for k, v := range r.env {
			result[k] = v
		}
		return result
	}
}

func defaultIsManifest(mf string) bool {
	if len(mf) > 0 {
		if s, err := os.Stat(mf); err == nil {
			return s.Mode().IsRegular()
		}
	}
	return false
}

func defaultIsDirectory(dir string) bool {
	if len(dir) > 0 {
		if s, err := os.Stat(dir); err == nil {
			return s.IsDir()
		}
	}
	return false
}

func discoverPaths(
	argv0, mf, dir string,
	isRunfilesManifest, isRunfilesDirectory func(string) bool) (out_manifest, out_directory string) {
	out_manifest = ""
	out_directory = ""
	mfValid := isRunfilesManifest(mf)
	dirValid := isRunfilesDirectory(dir)

	if !mfValid && !dirValid {
		if len(argv0) > 0 {
			mf = argv0 + ".runfiles/MANIFEST"
			dir = argv0 + ".runfiles"
			mfValid = isRunfilesManifest(mf)
			dirValid = isRunfilesDirectory(dir)
			if !mfValid {
				mf = argv0 + ".runfiles_manifest"
				mfValid = isRunfilesManifest(mf)
			}
		}
	}

	if !mfValid && !dirValid {
		return
	}

	if !mfValid {
		mf = dir + "/MANIFEST"
		mfValid = isRunfilesManifest(mf)
		if !mfValid {
			mf = dir + "_manifest"
			mfValid = isRunfilesManifest(mf)
		}
	}

	if !dirValid {
		const kSubstrLen = 9  // "_manifest" or "/MANIFEST"
		dir = mf[:len(mf) - kSubstrLen]
		dirValid = isRunfilesDirectory(dir)
	}

	if mfValid {
		out_manifest = mf
	}

	if dirValid {
		out_directory = dir
	}
	return
}
