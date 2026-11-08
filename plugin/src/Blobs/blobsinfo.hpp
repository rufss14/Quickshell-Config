#pragma once

#include <QObject>
#include <QQmlEngine>

// ── BlobsInfo ─────────────────────────────────────────────────────────────────
// Stage 1's entire payload: one singleton, one property, no shader, no visuals.
// Its only job is proving the pipe works — CMake finds Qt, qt_add_qml_module
// registers `Quicktest.Blobs`, the built module lands on QML_IMPORT_PATH, and
// `import Quicktest.Blobs` from shell.qml resolves to a real type instead of
// "module not installed". Everything downstream (the real BlobGroup/BlobRect
// SDF renderer, adapted from caelestia-dots/shell's Blobs module) is Stage 2,
// once this is confirmed working end to end.
class BlobsInfo : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QString version READ version CONSTANT)
    Q_PROPERTY(bool stage1 READ stage1 CONSTANT)

public:
    explicit BlobsInfo(QObject* parent = nullptr);

    QString version() const;
    bool stage1() const;
};
