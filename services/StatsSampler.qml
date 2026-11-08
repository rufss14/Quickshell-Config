import QtQuick

// ── StatsSampler ──────────────────────────────────────────────────────────────
// Holds the samplers a set of stats metrics reads (SysInfo, NetStats, SysStats'
// disk, DeviceBatteries) while it's `active`, and lets go of them when it isn't or
// when it's destroyed. Each of those is refcounted; this is the bookkeeping the
// stats pill used to do inline, so the button and the panel that replaced it can
// both hold what they show without either counting the other's references.
//
// `metrics` is the CONFIGURED list (Config.sidebarStatsMetrics), not what's
// available: a metric that has nothing to read right now (no peripherals found)
// still keeps its sampler, or it could never be found again.
//
// Devices are gated on their own switch: DeviceBatteries polls once a minute and
// UPower is free, so the button keeps them while merely auto-hidden, where the
// rest only run while something is on screen.
// ─────────────────────────────────────────────────────────────────────────────
QtObject {
    id: root

    property var  metrics: []
    property bool active: true
    property bool devicesActive: root.active

    readonly property bool wantsSys: root.active
        && root.metrics.some(m => ["cpu", "gpu", "ram", "swap", "diskio"].indexOf(m) >= 0)
    readonly property bool wantsNet:     root.active && root.metrics.indexOf("net") >= 0
    readonly property bool wantsDisk:    root.active && root.metrics.indexOf("disk") >= 0
    readonly property bool wantsDevices: root.devicesActive && root.metrics.indexOf("devices") >= 0

    property bool _sys: false
    property bool _net: false
    property bool _disk: false
    property bool _devices: false

    function _sync() {
        if (root.wantsSys !== root._sys) {
            if (root.wantsSys) SysInfo.acquire(); else SysInfo.release()
            root._sys = root.wantsSys
        }
        if (root.wantsNet !== root._net) {
            if (root.wantsNet) NetStats.acquire(); else NetStats.release()
            root._net = root.wantsNet
        }
        if (root.wantsDisk !== root._disk) {
            if (root.wantsDisk) SysStats.acquireDisk(); else SysStats.releaseDisk()
            root._disk = root.wantsDisk
        }
        if (root.wantsDevices !== root._devices) {
            if (root.wantsDevices) DeviceBatteries.acquire(); else DeviceBatteries.release()
            root._devices = root.wantsDevices
        }
    }
    onWantsSysChanged:     root._sync()
    onWantsNetChanged:     root._sync()
    onWantsDiskChanged:    root._sync()
    onWantsDevicesChanged: root._sync()
    Component.onCompleted: root._sync()
    Component.onDestruction: {
        if (root._sys) SysInfo.release()
        if (root._net) NetStats.release()
        if (root._disk) SysStats.releaseDisk()
        if (root._devices) DeviceBatteries.release()
    }
}
