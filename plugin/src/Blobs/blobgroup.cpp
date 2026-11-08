// Adapted verbatim from caelestia-dots/shell (plugin/src/Caelestia/Blobs/), GPLv3.
// See plugin/LICENSE and plugin/README.md.

#include "blobgroup.hpp"
#include "blobinvertedrect.hpp"
#include "blobshape.hpp"

BlobGroup::BlobGroup(QObject* parent)
    : QObject(parent) {}

BlobGroup::~BlobGroup() {
    for (auto* shape : std::as_const(m_shapes))
        shape->m_group = nullptr;
    if (m_invertedRect)
        static_cast<BlobShape*>(m_invertedRect)->m_group = nullptr;
}

void BlobGroup::setSmoothing(qreal s) {
    if (qFuzzyCompare(m_smoothing, s))
        return;
    m_smoothing = s;
    emit smoothingChanged();
    markDirty();
}

void BlobGroup::setColor(const QColor& c) {
    if (m_color == c)
        return;
    m_color = c;
    emit colorChanged();
    markDirty();
}

void BlobGroup::setBorderColor(const QColor& c) {
    if (m_borderColor == c)
        return;
    m_borderColor = c;
    emit borderColorChanged();
    markDirty();
}

void BlobGroup::setBorderWidth(qreal w) {
    if (qFuzzyCompare(m_borderWidth, w))
        return;
    m_borderWidth = w;
    emit borderWidthChanged();
    markDirty();
}

void BlobGroup::setCookies(const QList<qreal>& c) {
    if (m_cookies == c)
        return;
    m_cookies = c;
    emit cookiesChanged();
    markCookiesDirty();
}

void BlobGroup::setTone(int i, const QColor& c) {
    if (m_tones[i] == c)
        return;
    m_tones[i] = c;
    emit cookieTonesChanged();
    markCookiesDirty();
}

void BlobGroup::setCookieStroke(qreal w) {
    if (qFuzzyCompare(m_cookieStroke, w))
        return;
    m_cookieStroke = w;
    emit cookieStrokeChanged();
    markCookiesDirty();
}

// Both repaint every shape without restarting the spring physics, like the cookies: the sweep
// moves every frame while it runs.
void BlobGroup::setRimSweep(const QVector4D& v) {
    if (m_rimSweep == v)
        return;
    m_rimSweep = v;
    emit rimSweepChanged();
    markCookiesDirty();
}

void BlobGroup::setRimColor(const QColor& c) {
    if (m_rimColor == c)
        return;
    m_rimColor = c;
    emit rimSweepChanged();
    markCookiesDirty();
}

void BlobGroup::setCornerFill(bool e) {
    if (m_cornerFill == e)
        return;
    m_cornerFill = e;
    emit cornerFillChanged();
    markDirty();
}

void BlobGroup::addShape(BlobShape* shape) {
    if (!shape || m_shapes.contains(shape))
        return;
    m_shapes.append(shape);
    markDirty();
}

void BlobGroup::removeShape(BlobShape* shape) {
    m_shapes.removeOne(shape);
    markDirty();
}

void BlobGroup::setInvertedRect(BlobInvertedRect* rect) {
    if (m_invertedRect == rect)
        return;
    m_invertedRect = rect;
    markDirty();
}

void BlobGroup::clearInvertedRect(BlobInvertedRect* rect) {
    if (m_invertedRect != rect)
        return;
    m_invertedRect = nullptr;
    markDirty();
}

void BlobGroup::markDirty() {
    m_physicsUpdated = false;
    for (auto* shape : std::as_const(m_shapes)) {
        shape->polish();
        shape->update();
    }
    if (m_invertedRect) {
        static_cast<BlobShape*>(m_invertedRect)->polish();
        static_cast<BlobShape*>(m_invertedRect)->update();
    }
}

void BlobGroup::markCookiesDirty() {
    for (auto* shape : std::as_const(m_shapes)) {
        shape->polish();
        shape->update();
    }
    if (m_invertedRect) {
        static_cast<BlobShape*>(m_invertedRect)->polish();
        static_cast<BlobShape*>(m_invertedRect)->update();
    }
}

void BlobGroup::markShapeDirty(BlobShape* source) {
    m_physicsUpdated = false;

    source->polish();
    source->update();

    // Use cached padded rects to find spatial neighbors
    const float pad = static_cast<float>(m_smoothing) * 2.0f;
    const QRectF srcRect(static_cast<double>(source->m_cachedPaddedX - pad),
        static_cast<double>(source->m_cachedPaddedY - pad), static_cast<double>(source->m_cachedPaddedW + pad * 2.0f),
        static_cast<double>(source->m_cachedPaddedH + pad * 2.0f));

    for (auto* shape : std::as_const(m_shapes)) {
        if (shape == source)
            continue;
        const QRectF otherRect(static_cast<double>(shape->m_cachedPaddedX), static_cast<double>(shape->m_cachedPaddedY),
            static_cast<double>(shape->m_cachedPaddedW), static_cast<double>(shape->m_cachedPaddedH));
        if (srcRect.intersects(otherRect)) {
            shape->polish();
            shape->update();
        }
    }

    if (m_invertedRect && static_cast<BlobShape*>(m_invertedRect) != source) {
        static_cast<BlobShape*>(m_invertedRect)->polish();
        static_cast<BlobShape*>(m_invertedRect)->update();
    }
}

void BlobGroup::ensurePhysicsUpdated() {
    if (m_physicsUpdated)
        return;
    m_physicsUpdated = true;
    for (auto* shape : std::as_const(m_shapes))
        shape->updatePhysics();
}
