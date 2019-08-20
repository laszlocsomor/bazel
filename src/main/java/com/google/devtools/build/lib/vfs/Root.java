// Copyright 2018 The Bazel Authors. All rights reserved.
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
package com.google.devtools.build.lib.vfs;

import com.google.common.base.Objects;
import com.google.common.base.Preconditions;
import com.google.devtools.build.lib.skyframe.serialization.autocodec.AutoCodec;
import java.io.IOException;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.io.Serializable;
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import javax.annotation.Nullable;

/**
 * A root path used in {@link RootedPath} and in artifact roots.
 *
 * <p>A typical root could be the exec path, a package root, or an output root specific to some
 * configuration. We also support absolute roots for non-hermetic paths outside the user workspace.
 */
public abstract class Root implements Comparable<Root>, Serializable {

  /** Constructs a root from a path. */
  public static Root fromPath(Path path) {
    return new PathRoot(path);
  }

  /** Returns an absolute root. Can only be used with absolute path fragments. */
  public static Root absoluteRoot(FileSystem fileSystem) {
    return fileSystem.getAbsoluteRoot();
  }

  public static Root toFileSystem(Root root, FileSystem fileSystem) {
    return root.isAbsolute()
      ? new AbsoluteRoot(fileSystem)
      : new PathRoot(fileSystem.getPath(root.asPath().asFragment()));
  }

  /** Returns a path by concatenating the root and the root-relative path. */
  public abstract Path getRelative(PathFragment rootRelativePath);

  /** Returns a path by concatenating the root and the root-relative path. */
  public abstract Path getRelative(String rootRelativePath);

  /** Returns the relative path between the root and the given path. */
  public abstract PathFragment relativize(Path path);

  /** Returns the relative path between the root and the given absolute path fragment. */
  public abstract PathFragment relativize(PathFragment absolutePathFragment);

  /** Returns whether the given path is under this root. */
  public abstract boolean contains(Path path);

  /** Returns whether the given absolute path fragment is under this root. */
  public abstract boolean contains(PathFragment absolutePathFragment);

  public abstract BigInteger getFingerprint();

  /**
   * Returns the underlying path. Please avoid using this method.
   *
   * <p>Not all roots are backed by paths, so this may return null.
   */
  @Nullable
  public abstract Path asPath();

  public abstract boolean isAbsolute();

  public abstract Root correctCasing();

  /** Implementation of Root that is backed by a {@link Path}. */
  @AutoCodec
  public static final class PathRoot extends Root {
    private final Path path;
    private final BigInteger fingerprint;

    PathRoot(Path path) {
      this.path = path;
      // Can't use BigIntegerFingerprint because would cause cycle.
      this.fingerprint =
          new BigInteger(
              1,
              DigestHashFunction.MD5
                  .cloneOrCreateMessageDigest()
                  .digest(path.getPathString().getBytes(StandardCharsets.UTF_8)));
    }

    @Override
    public Path getRelative(PathFragment rootRelativePath) {
      return path.getRelative(rootRelativePath);
    }

    @Override
    public Path getRelative(String rootRelativePath) {
      return path.getRelative(rootRelativePath);
    }

    @Override
    public PathFragment relativize(Path path) {
      return path.relativeTo(this.path);
    }

    @Override
    public PathFragment relativize(PathFragment absolutePathFragment) {
      Preconditions.checkArgument(absolutePathFragment.isAbsolute());
      return absolutePathFragment.relativeTo(path.asFragment());
    }

    @Override
    public boolean contains(Path path) {
      return path.startsWith(this.path);
    }

    @Override
    public boolean contains(PathFragment absolutePathFragment) {
      return absolutePathFragment.isAbsolute()
          && absolutePathFragment.startsWith(path.asFragment());
    }

    @Override
    public Path asPath() {
      return path;
    }

    @Override
    public boolean isAbsolute() {
      return false;
    }

    @Override
    public Root correctCasing() {
      return new PathRoot(path.correctCasing());
    }

    @Override
    public String toString() {
      return path.toString();
    }

    @Override
    public int compareTo(Root o) {
      if (o instanceof AbsoluteRoot) {
        return 1;
      } else if (o instanceof PathRoot) {
        return path.compareTo(((PathRoot) o).path);
      } else {
        throw new AssertionError("Unknown Root subclass: " + o.getClass().getName());
      }
    }

    @Override
    public BigInteger getFingerprint() {
      return fingerprint;
    }

    @Override
    public boolean equals(Object o) {
      if (this == o) {
        return true;
      }
      if (o == null || getClass() != o.getClass()) {
        return false;
      }
      PathRoot pathRoot = (PathRoot) o;
      return path.equals(pathRoot.path);
    }

    @Override
    public int hashCode() {
      return path.hashCode();
    }
  }

  /** An absolute root of a file system. Can only resolve absolute path fragments. */
  @AutoCodec
  public static final class AbsoluteRoot extends Root {
    private static final BigInteger FINGERPRINT = new BigInteger("15742446659214128006");

    private FileSystem fileSystem; // Non-final for serialization

    AbsoluteRoot(FileSystem fileSystem) {
      this.fileSystem = fileSystem;
    }

    @Override
    public Path getRelative(PathFragment rootRelativePath) {
      Preconditions.checkArgument(rootRelativePath.isAbsolute());
      return fileSystem.getPath(rootRelativePath);
    }

    @Override
    public Path getRelative(String rootRelativePath) {
      return getRelative(PathFragment.create(rootRelativePath));
    }

    @Override
    public PathFragment relativize(Path path) {
      return path.asFragment();
    }

    @Override
    public PathFragment relativize(PathFragment absolutePathFragment) {
      Preconditions.checkArgument(absolutePathFragment.isAbsolute());
      return absolutePathFragment;
    }

    @Override
    public boolean contains(Path path) {
      return true;
    }

    @Override
    public boolean contains(PathFragment absolutePathFragment) {
      return absolutePathFragment.isAbsolute();
    }

    @Override
    public boolean isAbsolute() {
      return true;
    }

    @Override
    public Path asPath() {
      return null;
    }

    @Override
    public Root correctCasing() {
      return this;
    }

    @Override
    public String toString() {
      return "<absolute root>";
    }

    @Override
    public int compareTo(Root o) {
      if (o instanceof AbsoluteRoot) {
        return Integer.compare(fileSystem.hashCode(), ((AbsoluteRoot) o).fileSystem.hashCode());
      } else if (o instanceof PathRoot) {
        return -1;
      } else {
        throw new AssertionError("Unknown Root subclass: " + o.getClass().getName());
      }
    }

    @Override
    public BigInteger getFingerprint() {
      return FINGERPRINT;
    }

    @Override
    public boolean equals(Object o) {
      if (this == o) {
        return true;
      }
      if (o == null || getClass() != o.getClass()) {
        return false;
      }
      AbsoluteRoot that = (AbsoluteRoot) o;
      return Objects.equal(fileSystem, that.fileSystem);
    }

    @Override
    public int hashCode() {
      return Objects.hashCode(fileSystem);
    }

    @SuppressWarnings("unused")
    private void readObject(ObjectInputStream in) throws IOException {
      fileSystem = Path.getFileSystemForSerialization();
    }

    @SuppressWarnings("unused")
    private void writeObject(ObjectOutputStream out) throws IOException {
      Preconditions.checkState(
          fileSystem == Path.getFileSystemForSerialization(),
          "%s %s",
          fileSystem,
          Path.getFileSystemForSerialization());
    }
  }
}
