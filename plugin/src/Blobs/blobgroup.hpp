// Adapted verbatim from caelestia-dots/shell (plugin/src/Caelestia/Blobs/), GPLv3.
// See plugin/LICENSE and plugin/README.md.

#pragma once

#include <qcolor.h>
#include <qlist.h>
#include <qobject.h>
#include <qqmlengine.h>
#include <qvector4d.h>

class BlobShape;
class BlobInvertedRect;

class BlobGroup : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(qreal smoothing READ smoothing WRITE setSmoothing NOTIFY smoothingChanged)
    Q_PROPERTY(QColor color READ color WRITE setColor NOTIFY colorChanged)
    Q_PROPERTY(bool cornerFill READ cornerFill WRITE setCornerFill NOTIFY cornerFillChanged)
    Q_PROPERTY(QColor borderColor READ borderColor WRITE setBorderColor NOTIFY borderColorChanged)
    Q_PROPERTY(qreal borderWidth READ borderWidth WRITE setBorderWidth NOTIFY borderWidthChanged)
    // ── The cookie field, drawn in the material itself (Quicktest addition) ──────
    // A flat list, COOKIE_STRIDE numbers per shape, in scene (= screen) pixels:
    //   cx, cy, radius, rotation (radians, clockwise), petals, petal depth, opacity,
    //   tone + 4 * outlined
    // computed by the shell each frame (services/drift.js `pictures`). Each BlobShape
    // keeps the ones that touch its own quad, so a cookie is drawn exactly where the
    // merged silhouette is — fillets and bridges included — and nowhere else.
    Q_PROPERTY(QList<qreal> cookies READ cookies WRITE setCookies NOTIFY cookiesChanged)
    Q_PROPERTY(QColor cookieTone0 READ cookieTone0 WRITE setCookieTone0 NOTIFY cookieTonesChanged)
    Q_PROPERTY(QColor cookieTone1 READ cookieTone1 WRITE setCookieTone1 NOTIFY cookieTonesChanged)
    Q_PROPERTY(QColor cookieTone2 READ cookieTone2 WRITE setCookieTone2 NOTIFY cookieTonesChanged)
    Q_PROPERTY(QColor cookieTone3 READ cookieTone3 WRITE setCookieTone3 NOTIFY cookieTonesChanged)
    Q_PROPERTY(qreal cookieStroke READ cookieStroke WRITE setCookieStroke NOTIFY cookieStrokeChanged)
    // ── The rim sweep (Quicktest addition) ──────────────────────────────────────
    // A band of light that runs along the merged silhouette's outline: (centre x, centre y, radius,
    // width) in scene pixels. Outline pixels whose distance from the centre is within `width` of
    // `radius` brighten toward rimColor; rimColor's alpha is the strength, 0 draws nothing. The
    // shell animates `radius` outward from where a panel joins the bar when it opens. Only the
    // outline is touched, so with no border (borderWidth 0) it does nothing.
    Q_PROPERTY(QVector4D rimSweep READ rimSweep WRITE setRimSweep NOTIFY rimSweepChanged)
    Q_PROPERTY(QColor rimColor READ rimColor WRITE setRimColor NOTIFY rimSweepChanged)
    // ── The gradient (Quicktest addition) ───────────────────────────────────────
    // The fill as three colours along a line instead of one flat `color`. gradAxis is (x0, y0, dx, dy)
    // in scene pixels: t = dot(p - (x0, y0), (dx, dy)) / |(dx, dy)|², 0 at gradColor0 and 1 at
    // gradColor2, gradColor1 at t = gradMid. gradMid 0 (the default) is off: the fill is `color`. The
    // cookies and the outline draw over it as they do over the flat fill. Opaque, like `color`.
    Q_PROPERTY(QVector4D gradAxis READ gradAxis WRITE setGradAxis NOTIFY gradientChanged)
    Q_PROPERTY(qreal gradMid READ gradMid WRITE setGradMid NOTIFY gradientChanged)
    Q_PROPERTY(QColor gradColor0 READ gradColor0 WRITE setGradColor0 NOTIFY gradientChanged)
    Q_PROPERTY(QColor gradColor1 READ gradColor1 WRITE setGradColor1 NOTIFY gradientChanged)
    Q_PROPERTY(QColor gradColor2 READ gradColor2 WRITE setGradColor2 NOTIFY gradientChanged)

public:
    explicit BlobGroup(QObject* parent = nullptr);
    ~BlobGroup() override;

    qreal smoothing() const { return m_smoothing; }

    void setSmoothing(qreal s);

    QColor color() const { return m_color; }

    void setColor(const QColor& c);

    bool cornerFill() const { return m_cornerFill; }

    // Outline of the whole merged silhouette. See blob.frag.
    QColor borderColor() const { return m_borderColor; }

    void setBorderColor(const QColor& c);

    qreal borderWidth() const { return m_borderWidth; }

    void setBorderWidth(qreal w);

    void setCornerFill(bool e);

    static constexpr int COOKIE_STRIDE = 8;
    // Per shape: more than this in one quad are dropped (the uniform block is fixed).
    static constexpr int MAX_COOKIES = 24;

    const QList<qreal>& cookies() const { return m_cookies; }

    void setCookies(const QList<qreal>& c);

    QColor cookieTone0() const { return m_tones[0]; }
    QColor cookieTone1() const { return m_tones[1]; }
    QColor cookieTone2() const { return m_tones[2]; }
    QColor cookieTone3() const { return m_tones[3]; }

    void setCookieTone0(const QColor& c) { setTone(0, c); }
    void setCookieTone1(const QColor& c) { setTone(1, c); }
    void setCookieTone2(const QColor& c) { setTone(2, c); }
    void setCookieTone3(const QColor& c) { setTone(3, c); }

    const QColor* tones() const { return m_tones; }

    qreal cookieStroke() const { return m_cookieStroke; }

    void setCookieStroke(qreal w);

    QVector4D rimSweep() const { return m_rimSweep; }

    void setRimSweep(const QVector4D& v);

    QColor rimColor() const { return m_rimColor; }

    void setRimColor(const QColor& c);

    QVector4D gradAxis() const { return m_gradAxis; }
    void setGradAxis(const QVector4D& v);
    qreal gradMid() const { return m_gradMid; }
    void setGradMid(qreal m);
    QColor gradColor0() const { return m_gradColors[0]; }
    QColor gradColor1() const { return m_gradColors[1]; }
    QColor gradColor2() const { return m_gradColors[2]; }
    void setGradColor0(const QColor& c) { setGradColor(0, c); }
    void setGradColor1(const QColor& c) { setGradColor(1, c); }
    void setGradColor2(const QColor& c) { setGradColor(2, c); }
    const QColor* gradColors() const { return m_gradColors; }

    void addShape(BlobShape* shape);
    void removeShape(BlobShape* shape);

    void setInvertedRect(BlobInvertedRect* rect);
    void clearInvertedRect(BlobInvertedRect* rect);

    const QList<BlobShape*>& shapes() const { return m_shapes; }

    BlobInvertedRect* invertedRect() const { return m_invertedRect; }

    void markDirty();
    // Repaint every shape without restarting the spring physics (the cookies move every frame).
    void markCookiesDirty();
    void markShapeDirty(BlobShape* source);
    void ensurePhysicsUpdated();

signals:
    void smoothingChanged();
    void colorChanged();
    void cornerFillChanged();
    void borderColorChanged();
    void borderWidthChanged();
    void cookiesChanged();
    void cookieTonesChanged();
    void cookieStrokeChanged();
    void rimSweepChanged();
    void gradientChanged();

private:
    qreal m_smoothing = 32.0;
    QColor m_color{ 0x44, 0x88, 0xff };
    bool m_cornerFill = true;
    QColor m_borderColor{ 0, 0, 0, 0 };
    qreal m_borderWidth = 0.0;
    QList<qreal> m_cookies;
    QColor m_tones[4];
    qreal m_cookieStroke = 1.0;
    QVector4D m_rimSweep;
    QColor m_rimColor{ 255, 255, 255, 0 };
    QVector4D m_gradAxis{ 0, 0, 1, 0 };
    qreal m_gradMid = 0.0;
    QColor m_gradColors[3];

    void setGradColor(int i, const QColor& c);

    void setTone(int i, const QColor& c);
    QList<BlobShape*> m_shapes;
    BlobInvertedRect* m_invertedRect = nullptr;
    bool m_physicsUpdated = false;
};
