#!/usr/bin/env python
import os
import sys

env = SConscript("godot-cpp/SConstruct")

# For reference:
# - CCFLAGS are compilation flags shared between C and C++
# - CFLAGS are for C-specific compilation flags
# - CXXFLAGS are for C++-specific compilation flags
# - CPPFLAGS are for pre-processor flags
# - CPPDEFINES are for pre-processor defines
# - LINKFLAGS are for linking flags

addon_dir = "demo/addons/flow_nodes_editor"
native_src_dir = addon_dir + "/native/src"
bin_dir = addon_dir + "/bin"

# tweak this if you want to use different folders, or more folders, to store your source code in.
env.Append(CPPPATH=[native_src_dir])
common_sources = Glob(native_src_dir + "/*.cpp")

if env["platform"] == "macos":
    
    env.Append(CXXFLAGS=['-fexceptions'])

    # Add MacOS frameworks
    frameworks = [ 
                 #   'AuthenticationServices'
                 #, 'StoreKit'
                 ]
    for framework in frameworks:
        env.Append(LINKFLAGS=['-framework', framework])

    library = env.SharedLibrary(
        bin_dir + "/libflow.{}.{}.framework/libflow.{}.{}".format(
            env["platform"], env["target"], env["platform"], env["target"]
        ),
        source=common_sources,
    )

else:
    if env["platform"] == "windows":
        env.Append(CFLAGS=["/std:c11"])
    env.Append(CXXFLAGS=["-O2"])
    # nanoflann (gd_kdtree) requires exception support; godot-cpp disables it by
    # default on non-macOS targets (equivalent to passing disable_exceptions=no).
    if not env.get("is_msvc", False):
        env.Append(CXXFLAGS=["-fexceptions"])
    library = env.SharedLibrary(
        bin_dir + "/libflow{}{}".format(env["suffix"], env["SHLIBSUFFIX"]),
        source=common_sources,
    )

Default(library)
