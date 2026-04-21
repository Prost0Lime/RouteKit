package com.example.zapret2manager

data class ShellResult(
    val code: Int,
    val stdout: String,
    val stderr: String
)

data class ProxyProfile(
    val id: String,
    val name: String,
    val serverMeta: String,
    val isActive: Boolean,
    val groupId: String,
    val groupName: String,
    val server: String,
    val port: String
)

data class ProfilePingResult(
    val profileId: String,
    val pingMs: Int?,
    val endpoint: String
)

data class ServiceItem(
    val id: String,
    val name: String,
    val enabled: Boolean,
    val mode: String,
    val vpnProfile: String,
    val tcpStrategy: String,
    val udpStrategy: String,
    val stunStrategy: String,
    val isCustom: Boolean,
    val domainCount: Int,
    val autoIpCount: Int,
    val autoIpv6Count: Int,
    val coverageStatus: String,
    val ipv6Status: String
)

data class ServiceDetails(
    val id: String,
    val mode: String,
    val vpnProfile: String,
    val tcpStrategy: String,
    val udpStrategy: String,
    val stunStrategy: String,
    val tcpHostlist: String,
    val udpHostlist: String,
    val stunHostlist: String,
    val tcpIpset: String,
    val udpIpset: String,
    val stunIpset: String
)

data class ServiceCoverage(
    val domainCount: Int,
    val autoIpCount: Int,
    val totalIpCount: Int,
    val autoIpv6Count: Int,
    val coverageStatus: String,
    val ipv6Status: String,
    val tcpStaticCount: Int,
    val udpStaticCount: Int,
    val stunStaticCount: Int,
    val unresolvedCount: Int,
    val conflictCount: Int,
    val modeConflictCount: Int
)

data class DomainValidation(
    val totalDomains: Int,
    val uniqueDomains: Int,
    val invalidDomains: List<String>,
    val duplicateDomains: List<String>,
    val conflicts: List<String>,
    val modeConflictCount: Int
) {
    val hasIssues: Boolean
        get() = invalidDomains.isNotEmpty() || duplicateDomains.isNotEmpty() || conflicts.isNotEmpty()
}

data class StrategyItem(
    val id: String,
    val description: String
) {
    override fun toString(): String = if (description.isBlank()) id else "$id — $description"
}

data class ZapretProfileItem(
    val id: String,
    val name: String,
    val summary: String
) {
    override fun toString(): String =
        if (summary.isBlank()) "$name ($id)" else "$name ($id)\n$summary"
}

data class HealthStatus(
    val rawJson: String,
    val zapret: String,
    val proxy: String,
    val transproxy: String,
    val dnsRedirect: String,
    val ipv6Block: String,
    val routingEnabled: String,
    val routingMode: String,
    val zapretProfile: String,
    val zapretProfileName: String,
    val activeProfileId: String,
    val activeProfileName: String,
    val activeProfileServer: String,
    val activeProfileGroup: String,
    val serviceZapretCount: String,
    val serviceVpnCount: String,
    val serviceDirectCount: String,
    val customServiceCount: String,
    val proxyDomainsCount: String,
    val directDomainsCount: String,
    val autoIpsetTotal: String,
    val autoIpv6IpsetTotal: String,
    val internet: String,
    val timestamp: String
)


enum class UiActionPhase {
    IDLE,
    APPLYING,
    STARTING,
    STOPPING,
    RESTARTING,
    REBUILDING,
    IMPORTING,
    SAVING
}
