package com.example.zapret2manager

object ModulePaths {
    const val MODULE_BASE = "/data/adb/modules/zapret2_manager/files"
    const val SCRIPTS = "$MODULE_BASE/scripts"
    const val CONFIG = "$MODULE_BASE/config"
    const val RUNTIME = "$MODULE_BASE/runtime"
    const val SERVICES = "$CONFIG/service_modes"
    const val TCP_INI = "$CONFIG/strategies/strategies-tcp.ini"
    const val UDP_INI = "$CONFIG/strategies/strategies-udp.ini"
    const val STUN_INI = "$CONFIG/strategies/strategies-stun.ini"
}
