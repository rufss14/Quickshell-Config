# ── quicktest-blobs ──────────────────────────────────────────────────────────
# A native Qt6 QML module, built and installed OUTSIDE the system Qt path (see
# scripts/build-blobs-plugin.sh) so this repo stays "clone it and point Quickshell
# at it" for everyone who doesn't build the plugin — the shell degrades to the
# plain QML morph (Card grow + FrameFusion weld) when this module isn't present,
# rather than failing to start.
#
# Stage 1 proved the toolchain end to end with a trivial singleton (BlobsInfo).
# Stage 2 (current) adds the real SDF blob-union renderer — BlobGroup/BlobRect/
# BlobInvertedRect/BlobMaterial and shaders/blob.{frag,vert} — adapted from
# caelestia-dots/shell's `Caelestia.Blobs` module, GPLv3 (see LICENSE in this
# directory and README.md for what was and wasn't changed).
# ─────────────────────────────────────────────────────────────────────────────
cmake_minimum_required(VERSION 3.19)
project(quicktest-blobs LANGUAGES CXX)

include(GNUInstallDirs)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_AUTOMOC ON)

# Where the built module lands. NOT a literal — scripts/build-blobs-plugin.sh
# computes this from $XDG_CACHE_HOME/$HOME at BUILD time and passes it in via
# -DINSTALL_QMLDIR=..., so nothing here bakes in one machine's home directory.
# Defaulting to a build-tree-local path means a bare `cmake --build .` still
# produces something inspectable even if nobody sets it.
set(INSTALL_QMLDIR "${CMAKE_BINARY_DIR}/qml" CACHE PATH
    "Where the built QML module tree is installed")

# ShaderTools compiles shaders/blob.{frag,vert} to .qsb at build time (qt_add_shaders,
# in src/Blobs/CMakeLists.txt) — Qt's cross-backend shader format, not raw GLSL shipped
# as-is, so the same .qsb works whether Quickshell's RHI backend is OpenGL or Vulkan.
find_package(Qt6 REQUIRED COMPONENTS Core Qml Quick ShaderTools)

qt_standard_project_setup(REQUIRES 6.5)

include(cmake/qml-module.cmake)

add_subdirectory(src/Blobs)
