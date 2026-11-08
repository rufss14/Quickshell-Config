#include "blobsinfo.hpp"

BlobsInfo::BlobsInfo(QObject* parent)
    : QObject(parent) {
}

QString BlobsInfo::version() const {
    return QStringLiteral("0.1.0-stage1");
}

bool BlobsInfo::stage1() const {
    return true;
}
