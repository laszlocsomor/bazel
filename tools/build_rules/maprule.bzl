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

r"""Maprule implementation using Starlark.

Attribute documentation: see at the bottom where the attributes are defined.

Example use:

load("//tools/build_rules:maprule.bzl", "maprule")

maprule(
    name = "opensource",
    srcs = [":gen_licence"],
    outs = {
        "with_licence": "{default}.with_licence.cc",
        "digest": "md5/{src_dir}/{src_name_noext}.md5",
    },
    cmd = " ; ".join([
        "cat $(SRCS) $(src) > $(with_licence)",
        "cat $(SRCS) $(src) | md5sum | awk '{print $$1}' > $(digest)",
    ]),
    foreach_srcs = [":source_files"],
    language = "bash",
)

filegroup(
    name = "source_files",
    srcs = glob(["**/*.cc"]) + ["//foo/bar:source_files"],
)

genrule(
    name = "gen_licence",
    outs = ["licence.txt"],
    cmd = "echo \"/* Licence: don't be evil. */\" > $@",
)
"""

def _compute_common_make_variables(srcs):
    """Returns a dict with Make Variables common to all per-source actions."""

    # TODO: cmd_helper is deprecated
    return {"SRCS": cmd_helper.join_paths(" ", srcs)}

def _add_make_var(var_dict, name, value, attr_name):
    """Helper function to add new Make variables."""
    if name in var_dict:
        fail("duplicate Make Variable \"%s\"" % name, attr = attr_name)
    return {name: value}

def _compute_make_variables(common_vars, foreach_src, templates_dict):
    """Resolves Make Variables in the command string."""
    variables = dict(common_vars)

    # Add the user-defined Make Variables for the foreach_src's outputs.
    for makevar in templates_dict:
        variables.update(_add_make_var(
            variables,
            makevar,
            templates_dict[makevar].path,
            "outs",
        ))

    # Add the $(@) makevar if there's only one output per source.
    if len(templates_dict) == 1:
        variables.update(_add_make_var(
            variables,
            "@",
            templates_dict.values()[0].path,
            "outs",
        ))

    # Add the $(src) makevar for foreach_src.
    variables.update(_add_make_var(variables, "src", foreach_src.path, "foreach_srcs"))
    return variables

def _is_relative(p):
    """Tells whether `p` is a relative path.

    This function is aware of both Unix and Windows paths.

    Args:
      p: string; representing a path

    Returns:
      bool; True if `p` is a non-empty string referring to a relative path,
      False otherwise.
    """
    return p and p[0] != "/" and p[0] != "\\" and (
        len(p) < 2 or not p[0].isalpha() or p[1] != ":"
    )

def _outs_error(key, value, message):
    prefix = "in template declaration (\"%s\": \"%s\"): " % (key, value)
    fail(prefix + message, attr = "outs")

def _get_outs_templates(ctx):
    """Returns a dict of the output templates + checks them and reports errors."""
    result = {}
    values = {}
    for key, value in ctx.attr.outs.items():
        if not value:
            _outs_error(key, value, "output path should not be empty")
        if not _is_relative(value):
            _outs_error(key, value, "output path should be relative")
        if ".." in value:
            _outs_error(key, value, "output path should not contain uplevel references")
        if value in values:
            _outs_error(
                    key, value,
                    ("output path for key \"%s\" is already used " % key) +
                        ("for key \"%s\"" % values[key]))
        result[key] = value
        values[value] = key
    return result

def _create_outputs(ctx, foreach_srcs, templates):
    """Creates all output files for the rule.

    For each File in `foreach_srcs`, this method expands placeholders in every
    output template in `templates` and creates the corresponding rule output
    file.

    For N files in `foreach_srcs` and M output templates in `templates`, this
    method creates N*M File objects.

    Args:
      ctx: the rule context object
      foreach_srcs: list of Files; all files in the `foreach_srcs` attribute
      templates: {string: string} dict; key-value pairs from the `outs`
          attribute

    Returns:
      {string: {string: string}} dict of dicts; keys in the outer dict are the
      elements from `foreach_srcs`, values in the outer dict are dictionaries
      corresponding to the outputs of this key; keys in the inner dict are
      output template names (keys from `templates`), values are the resolved
      output paths for the corresponding `foreach_srcs` entry (the corresponding
      key in the outer dict).
    """
    result = {}
    all_outputs = {}  # map output Files to the (src, template) generating them
    out_path_prefix = ctx.label.name + "_out/"
    for src in foreach_srcs:
        outs_for_src = {}

        for template_name, template in templates.items():
            out_path = template.format(
                default = src.path,  # same as "{src_dir}/{src_name}"
                src_dir = src.dirname,
                src_name = src.basename,
                src_name_noext = (src.basename[:-len(src.extension) - 1] if len(src.extension) else src.basename),
            )
            if out_path in all_outputs:
                existing = all_outputs[out_path]
                fail(
                    "\n".join([
                        "output file generated multiple times:",
                        "  output file: " + out_path,
                        "  input 1: " + existing[0].short_path,
                        "  output template 1: " + existing[1],
                        "  input 2: " + src.short_path,
                        "  output template 2: " + template_name,
                    ]),
                    attr = "outs",
                )
            all_outputs[out_path] = (src, template_name)
            output = ctx.actions.declare_file(out_path_prefix + out_path)
            outs_for_src[template_name] = output
        result[src] = outs_for_src
    return result

def _create_action(ctx, src, common_srcs, outs_dict, makevars, message):
    """Creates the generating action for one `foreach_srcs` source file.

    Args:
      ctx: the rule context object
      src: File; a single entry from the `foreach_srcs` attribute
      common_srcs: list or depset of Files; the files from the `srcs` attribute
      outs_dict: TODO
      makevars: TODO
      message: TODO

    Returns:
      TODO
    """
    resolved_inputs, argv, runfiles_manifests = ctx.resolve_command(
        command = ctx.attr.cmd,
        attribute = "cmd",
        expand_locations = True,
        make_variables = _compute_make_variables(makevars, src, outs_dict),
        tools = ctx.attr.tools,
        label_dict = {},
    )  # TODO(bazel-team): labels we pass here are not used. At least in 2014 they weren't.

    ctx.actions.run_shell(
        inputs = depset(
            direct = [src],
            transitive = [common_srcs, depset(resolved_inputs or [])],
        ),
        outputs = outs_dict.values(),
        env = ctx.configuration.default_shell_env,
        command = " ".join([str(x) for x in argv]),
        progress_message = "%s %s" % (message, ctx.label),
        mnemonic = "Maprule",
        input_manifests = runfiles_manifests or [],
    )

    return depset(outs_dict.values())

def _impl(ctx):
    # From "srcs": merge the depsets in the DefaultInfo.files of the targets.
    common_srcs = depset(transitive = [
        t[DefaultInfo].files
        for t in ctx.attr.srcs
    ])

    # From "foreach_srcs": flatten the depsets of DefaultInfo.files of the
    # targets and merge to a single list. We have to iterate over them later.
    foreach_srcs = ctx.files.foreach_srcs

    # Create the outputs for the foreach_srcs.
    foreach_src_outs_dicts = _create_outputs(
        ctx,
        foreach_srcs,
        _get_outs_templates(ctx),
    )

    message = ctx.attr.message or "Executing maprule"
    common_makevars = _compute_common_make_variables(common_srcs)

    files_to_build = depset(
        transitive = [
            _create_action(ctx, src, common_srcs, foreach_src_outs_dicts[src], common_makevars, message)
            for src in foreach_srcs
        ],
    )

    return [DefaultInfo(files = files_to_build)]

maprule = rule(
    implementation = _impl,
    attrs = {
        # List of labels; optional.
        # Defines the set of sources that are available to all actions created
        # by this rule.
        #
        # This attribute would better be called "common_srcs", but $(location)
        # expansion only works for srcs, deps, data and tools.
        "srcs": attr.label_list(
            allow_empty = True,
            allow_files = True,
            doc = "TODO",
        ),

        # List of labels; required.
        # Defines the set of sources that will be processed one by one in
        # parallel to produce the templated outputs. For each action created
        # by this rule only one of these sources will be provided.
        #
        # This attribute would better be called "srcs", but that we need for
        # the common srcs in order to make $(location) expansion work.
        "foreach_srcs": attr.label_list(
            allow_empty = False,
            allow_files = True,
            mandatory = True,
            doc = "TODO",
        ),

        # List of labels; optional.
        # Tools used by the command in "cmd". Similar to genrule.tools
        "tools": attr.label_list(cfg = "host", allow_files = True),

        # Dict of output templates; required.
        #
        # Entries in this dictionary define the path templates for the outputs
        # of this rule. Every template is relative to bazel-genfiles/P/R.outputs
        # where P is the maprule's package and R is the maprule's name.
        #
        # Each dict key defines a Make Variable that identifies the output file
        # in `cmd`. The dict value is the path of the output file.
        # The dict value must be a relative path and may contain placeholders
        # that Bazel replaces with certain path fragments.
        # The supported placeholders and their replacements are:
        # - "{default}": same as "{src_dir}/{src_name}"
        # - "{src_dir}": root-relative directory path of the source file and a
        #   trailing "/"
        # - "{src_name}": basename of the source file
        # - "{src_name_noext}": basename of the source file without its
        #   extension
        "outs": attr.string_dict(
            allow_empty = False,
            mandatory = True,
            doc = "TODO",
        ),

        # String; required.
        # The shell command to execute for each file of the "foreach_srcs" that
        # produces the outputs. Similar to genrule.cmd
        "cmd": attr.string(mandatory = True),

        # TODO
        # "language": attr.string(
        #     mandatory = True,
        #     values = ["bash", "cmd", "powershell"],
        # ),

        # String; optional.
        # The progress message to display when the actions are being executed.
        "message": attr.string(),

        # List of strings; optional.
        # See the common attribute definitions in the Build Encyclopedia.
        # "output_licenses": attr.license(),
    },
)
