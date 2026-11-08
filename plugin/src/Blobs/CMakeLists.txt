# Stage 2: the real SDF blob-union renderer, adapted from caelestia-dots/shell's
# `Caelestia.Blobs` module (GPLv3 — see plugin/LICENSE and plugin/README.md).
# BlobsInfo (Stage 1's smoke test) stays registered alongside it — harmless, and
# still useful as a "is the module actually loaded" check from QML.
qml_module(quicktest-blobs
    URI Quicktest.Blobs
    SOURCES
        blobsinfo.hpp
        blobsinfo.cpp
        blobshape.hpp
        blobshape.cpp
        blobgroup.hpp
        blobgroup.cpp
        blobrect.hpp
        blobrect.cpp
        blobinvertedrect.hpp
        blobinvertedrect.cpp
        blobmaterial.hpp
        blobmaterial.cpp
    LIBRARIES
        Qt::Quick
)

qt_add_shaders(quicktest-blobs "quicktest_blob_shaders"
    BATCHABLE OPTIMIZED NOHLSL NOMSL
    GLSL "300es,330"
    PREFIX "/"
    FILES
        shaders/blob.frag
        shaders/blob.vert
)
