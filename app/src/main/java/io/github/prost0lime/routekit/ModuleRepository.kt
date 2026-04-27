package io.github.prost0lime.routekit

import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

class ModuleRepository {

    fun healthcheck(): String = sh("sh ${ModulePaths.SCRIPTS}/healthcheck.sh").stdout.ifBlank { "no output" }

    fun moduleVersion(): String {
        val out = sh("grep '^version=' ${ModulePaths.MODULE_BASE}/../module.prop 2>/dev/null || grep '^version=' ${ModulePaths.MODULE_BASE}/module.prop 2>/dev/null").stdout
        return out.lineSequence()
            .map { it.trim() }
            .firstOrNull { it.startsWith("version=") }
            ?.substringAfter("=")
            .orEmpty()
    }

    fun fetchLatestRelease(): UpdateInfo {
        val connection = (URL("https://api.github.com/repos/Prost0Lime/RouteKit/releases/latest").openConnection() as HttpURLConnection).apply {
            connectTimeout = 8000
            readTimeout = 8000
            requestMethod = "GET"
            setRequestProperty("Accept", "application/vnd.github+json")
            setRequestProperty("User-Agent", "RouteKit")
        }
        var responseCode = -1
        val body = try {
            responseCode = connection.responseCode
            val stream = if (responseCode in 200..299) connection.inputStream else connection.errorStream
            stream.bufferedReader().use { it.readText() }
        } finally {
            connection.disconnect()
        }
        if (responseCode !in 200..299) {
            throw IllegalStateException("GitHub releases request failed: HTTP $responseCode")
        }
        val json = JSONObject(body)
        val tag = json.optString("tag_name")
        if (tag.isBlank()) {
            throw IllegalStateException("GitHub latest release has no tag_name")
        }
        val assets = json.optJSONArray("assets")
        var apkUrl: String? = null
        var moduleUrl: String? = null
        if (assets != null) {
            for (i in 0 until assets.length()) {
                val asset = assets.optJSONObject(i) ?: continue
                val name = asset.optString("name")
                val url = asset.optString("browser_download_url")
                if (name.endsWith(".apk")) apkUrl = url
                if (name.endsWith(".zip") && name.contains("module", ignoreCase = true)) moduleUrl = url
            }
        }
        return UpdateInfo(
            version = tag.removePrefix("v"),
            tag = tag,
            releaseUrl = json.optString("html_url"),
            apkUrl = apkUrl,
            moduleUrl = moduleUrl
        )
    }

    fun healthcheckParsed(): HealthStatus {
        val raw = healthcheck()
        return try {
            val json = JSONObject(raw)
            HealthStatus(
                rawJson = raw,
                zapret = json.optString("zapret"),
                proxy = json.optString("proxy"),
                transproxy = json.optString("transproxy"),
                dnsRedirect = json.optString("dns_redirect"),
                ipv6Block = json.optString("ipv6_block"),
                routingEnabled = json.optString("routing_enabled"),
                routingMode = json.optString("routing_mode"),
                zapretProfile = json.optString("zapret_profile"),
                zapretProfileName = json.optString("zapret_profile_name"),
                activeProfileId = json.optString("active_profile_id"),
                activeProfileName = json.optString("active_profile_name"),
                activeProfileServer = json.optString("active_profile_server"),
                activeProfileGroup = json.optString("active_profile_group"),
                serviceZapretCount = json.optString("service_zapret_count"),
                serviceVpnCount = json.optString("service_vpn_count"),
                serviceDirectCount = json.optString("service_direct_count"),
                customServiceCount = json.optString("custom_service_count"),
                proxyDomainsCount = json.optString("proxy_domains_count"),
                directDomainsCount = json.optString("direct_domains_count"),
                autoIpsetTotal = json.optString("auto_ipset_total"),
                autoIpv6IpsetTotal = json.optString("auto_ipv6_ipset_total"),
                internet = json.optString("internet"),
                timestamp = json.optString("timestamp")
            )
        } catch (_: Throwable) {
            HealthStatus(
                rawJson = raw,
                zapret = "?",
                proxy = "?",
                transproxy = "?",
                dnsRedirect = "?",
                ipv6Block = "?",
                routingEnabled = "?",
                routingMode = "?",
                zapretProfile = "",
                zapretProfileName = "",
                activeProfileId = "",
                activeProfileName = "",
                activeProfileServer = "",
                activeProfileGroup = "",
                serviceZapretCount = "0",
                serviceVpnCount = "0",
                serviceDirectCount = "0",
                customServiceCount = "0",
                proxyDomainsCount = "0",
                directDomainsCount = "0",
                autoIpsetTotal = "0",
                autoIpv6IpsetTotal = "0",
                internet = "?",
                timestamp = ""
            )
        }
    }

    fun listProfiles(): List<ProxyProfile> {
        val out = sh("sh ${ModulePaths.SCRIPTS}/list_profiles.sh").stdout
        return out.lineSequence()
            .map { it.trim() }
            .filter { it.isNotBlank() && it != "no profiles" }
            .mapNotNull { line ->
                val active = line.startsWith("*")
                val clean = line.removePrefix("*").removePrefix(" ").trim()
                val parts = clean.split("|").map { it.trim() }
                if (parts.size < 3) return@mapNotNull null
                fun valueOf(prefix: String): String =
                    parts.firstOrNull { it.startsWith("$prefix=") }?.substringAfter('=', "").orEmpty()
                val groupId = valueOf("group_id").ifBlank { "-" }
                val groupName = valueOf("group").ifBlank { if (groupId == "-") "Без группы" else groupId }
                val server = valueOf("server")
                val port = valueOf("port")
                ProxyProfile(
                    id = parts[0],
                    name = parts[1],
                    serverMeta = parts[2],
                    isActive = active,
                    groupId = groupId,
                    groupName = groupName,
                    server = server,
                    port = port
                )
            }
            .toList()
    }

    fun pingProfileGroup(groupId: String): List<ProfilePingResult> {
        val out = sh("sh ${ModulePaths.SCRIPTS}/ping_group_profiles.sh ${shellQuote(groupId)}").stdout
        return out.lineSequence()
            .map { it.trim() }
            .filter { it.isNotBlank() && it != "no profiles" }
            .mapNotNull { line ->
                val parts = line.split("|").map { it.trim() }
                if (parts.size < 3) return@mapNotNull null
                ProfilePingResult(
                    profileId = parts[0],
                    pingMs = parts[1].toIntOrNull(),
                    endpoint = parts[2]
                )
            }
            .toList()
    }

    fun importSubscription(url: String, groupName: String?): ShellResult {
        val escapedUrl = shellQuote(url)
        val cmd = if (groupName.isNullOrBlank()) {
            "sh ${ModulePaths.SCRIPTS}/import_group_url.sh $escapedUrl"
        } else {
            "sh ${ModulePaths.SCRIPTS}/import_group_url.sh $escapedUrl ${shellQuote(groupName)}"
        }
        return sh(cmd)
    }

    fun importVless(uri: String, profileName: String?): ShellResult {
        val cmd = if (profileName.isNullOrBlank()) {
            "sh ${ModulePaths.SCRIPTS}/import_vless.sh ${shellQuote(uri)}"
        } else {
            "sh ${ModulePaths.SCRIPTS}/import_vless.sh ${shellQuote(uri)} ${shellQuote(profileName)}"
        }
        return sh(cmd)
    }

    fun importGroupFile(filePath: String, groupName: String?): ShellResult {
        val cmd = if (groupName.isNullOrBlank()) {
            "sh ${ModulePaths.SCRIPTS}/import_group_file.sh ${shellQuote(filePath)}"
        } else {
            "sh ${ModulePaths.SCRIPTS}/import_group_file.sh ${shellQuote(filePath)} ${shellQuote(groupName)}"
        }
        return sh(cmd)
    }

    fun setActiveProfile(profileId: String): ShellResult =
        sh("sh ${ModulePaths.SCRIPTS}/set_active_profile.sh ${shellQuote(profileId)}")

    fun diagnoseProfile(profileId: String): ShellResult =
        sh("sh ${ModulePaths.SCRIPTS}/diagnose_profile.sh ${shellQuote(profileId)}")

    fun deleteProfile(profileId: String): ShellResult =
        sh("sh ${ModulePaths.SCRIPTS}/delete_profile.sh ${shellQuote(profileId)}")

    fun listServices(): List<ServiceItem> {
        val out = sh("sh ${ModulePaths.SCRIPTS}/list_services.sh").stdout
        return out.lineSequence()
            .map { it.trim() }
            .filter { it.isNotBlank() }
            .mapNotNull { line ->
                val parts = line.split("|").map { it.trim() }
                if (parts.size < 9) return@mapNotNull null
                fun valueOf(text: String) = text.substringAfter('=', "")
                val serviceId = parts[0]
                ServiceItem(
                    id = serviceId,
                    name = parts[1],
                    enabled = valueOf(parts[2]).toBoolean(),
                    mode = valueOf(parts[3]),
                    vpnProfile = valueOf(parts[4]),
                    tcpStrategy = valueOf(parts[5]),
                    udpStrategy = valueOf(parts[6]),
                    stunStrategy = valueOf(parts[7]),
                    isCustom = valueOf(parts[8]).toBoolean(),
                    domainCount = valueOf(parts.getOrElse(9) { "domains=0" }).toIntOrNull() ?: 0,
                    autoIpCount = valueOf(parts.getOrElse(10) { "auto_ip=0" }).toIntOrNull() ?: 0,
                    autoIpv6Count = valueOf(parts.getOrElse(11) { "auto_ipv6=0" }).toIntOrNull() ?: 0,
                    coverageStatus = valueOf(parts.getOrElse(12) { "coverage=n/a" }),
                    ipv6Status = valueOf(parts.getOrElse(13) { "ipv6=n/a" })
                )
            }
            .toList()
    }

    fun getServiceDetails(serviceId: String): ServiceDetails {
        val out = sh("sh ${ModulePaths.SCRIPTS}/show_service_mode.sh ${shellQuote(serviceId)}").stdout
        val map = parseVarFile(out)
        return ServiceDetails(
            id = map["SERVICE_ID"].orEmpty(),
            mode = map["MODE"].orEmpty(),
            vpnProfile = map["VPN_PROFILE"].orEmpty(),
            tcpStrategy = map["TCP_STRATEGY"].orEmpty(),
            udpStrategy = map["UDP_STRATEGY"].orEmpty(),
            stunStrategy = map["STUN_STRATEGY"].orEmpty(),
            tcpHostlist = map["TCP_HOSTLIST"].orEmpty(),
            udpHostlist = map["UDP_HOSTLIST"].orEmpty(),
            stunHostlist = map["STUN_HOSTLIST"].orEmpty(),
            tcpIpset = map["TCP_IPSET"].orEmpty(),
            udpIpset = map["UDP_IPSET"].orEmpty(),
            stunIpset = map["STUN_IPSET"].orEmpty()
        )
    }

    fun loadServiceDomains(serviceId: String): String =
        sh("sh ${ModulePaths.SCRIPTS}/show_service_domains.sh ${shellQuote(serviceId)}").stdout

    fun saveServiceDomains(serviceId: String, domainsText: String): ShellResult {
        val temp = File.createTempFile("zapret_domains_", ".txt")
        temp.writeText(domainsText)
        val result = sh("sh ${ModulePaths.SCRIPTS}/save_service_domains.sh ${shellQuote(serviceId)} ${shellQuote(temp.absolutePath)}")
        temp.delete()
        return result
    }

    fun getServiceCoverage(serviceId: String): ServiceCoverage {
        val out = sh("sh ${ModulePaths.SCRIPTS}/show_service_coverage.sh ${shellQuote(serviceId)}").stdout
        val map = parseVarFile(out)
        return ServiceCoverage(
            domainCount = map["DOMAIN_COUNT"]?.toIntOrNull() ?: 0,
            autoIpCount = map["AUTO_IP_COUNT"]?.toIntOrNull() ?: 0,
            totalIpCount = map["TOTAL_IP_COUNT"]?.toIntOrNull() ?: 0,
            autoIpv6Count = map["AUTO_IPV6_COUNT"]?.toIntOrNull() ?: 0,
            coverageStatus = map["COVERAGE_STATUS"].orEmpty(),
            ipv6Status = map["IPV6_STATUS"].orEmpty(),
            tcpStaticCount = map["TCP_STATIC_COUNT"]?.toIntOrNull() ?: 0,
            udpStaticCount = map["UDP_STATIC_COUNT"]?.toIntOrNull() ?: 0,
            stunStaticCount = map["STUN_STATIC_COUNT"]?.toIntOrNull() ?: 0,
            unresolvedCount = map["UNRESOLVED_COUNT"]?.toIntOrNull() ?: 0,
            conflictCount = map["CONFLICT_COUNT"]?.toIntOrNull() ?: 0,
            modeConflictCount = map["MODE_CONFLICT_COUNT"]?.toIntOrNull() ?: 0
        )
    }

    fun diagnoseService(serviceId: String): ShellResult =
        sh("sh ${ModulePaths.SCRIPTS}/diagnose_service.sh ${shellQuote(serviceId)}")

    fun repairService(serviceId: String): ShellResult =
        sh("sh ${ModulePaths.SCRIPTS}/repair_service.sh ${shellQuote(serviceId)}")

    fun loadModuleSettings(): ModuleSettings {
        val out = sh("sh ${ModulePaths.SCRIPTS}/show_module_settings.sh").stdout
        val map = parseVarFile(out)
        return ModuleSettings(
            collectIpv6 = map["COLLECT_IPV6"]?.toBooleanStrictOrNull() ?: true,
            dnsResolveRepeat = map["DNS_RESOLVE_REPEAT"]?.toIntOrNull()?.coerceIn(1, 10) ?: 3,
            ipv6BlockEnabled = map["IPV6_BLOCK_ENABLED"]?.toBooleanStrictOrNull() ?: true
        )
    }

    fun saveModuleSettings(settings: ModuleSettings): ShellResult =
        sh(
            "sh ${ModulePaths.SCRIPTS}/set_module_settings.sh " +
                "collect_ipv6=${settings.collectIpv6} " +
                "dns_repeat=${settings.dnsResolveRepeat.coerceIn(1, 10)} " +
                "ipv6_block=${settings.ipv6BlockEnabled}"
        )

    fun validateServiceDomains(serviceId: String, domainsText: String): DomainValidation {
        fun normalizeEntry(value: String): String {
            val trimmed = value.trim().lowercase().removeSuffix(".")
            return when {
                trimmed.startsWith("suffix:") -> "suffix:" + trimmed.removePrefix("suffix:").removePrefix("*.").removeSuffix(".")
                trimmed.startsWith("*.") -> "suffix:" + trimmed.removePrefix("*.").removeSuffix(".")
                else -> trimmed
            }
        }

        fun isValidEntry(value: String): Boolean {
            val exactRegex = Regex(
                "^(?=.{1,253}$)(?!-)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.)+(?:[a-z]{2,63}|xn--[a-z0-9-]{2,59})$",
                RegexOption.IGNORE_CASE
            )
            if (value.startsWith("suffix:")) {
                val suffix = value.removePrefix("suffix:")
                return exactRegex.matches(suffix)
            }
            return exactRegex.matches(value)
        }

        val lines = domainsText.lineSequence().map { it.trim() }.filter { it.isNotBlank() && !it.startsWith("#") }.toList()
        val normalized = lines.map(::normalizeEntry)
        val duplicateDomains = normalized.groupingBy { it }.eachCount()
            .filterValues { it > 1 }
            .keys
            .sorted()
        val invalidDomains = normalized.filterNot(::isValidEntry).distinct().sorted()

        val temp = File.createTempFile("zapret_validate_", ".txt")
        temp.writeText(domainsText)
        val out = sh("sh ${ModulePaths.SCRIPTS}/validate_service_domains.sh ${shellQuote(serviceId)} ${shellQuote(temp.absolutePath)}").stdout
        temp.delete()
        val conflicts = out.lineSequence().map { it.trim() }.filter { it.isNotBlank() }.toList()
        val modeConflictCount = conflicts.count { it.split("|").getOrElse(4) { "" } == "mode_conflict" }
        return DomainValidation(
            totalDomains = normalized.size,
            uniqueDomains = normalized.distinct().size,
            invalidDomains = invalidDomains,
            duplicateDomains = duplicateDomains,
            conflicts = conflicts,
            modeConflictCount = modeConflictCount
        )
    }

    fun loadStrategies(layer: String): List<StrategyItem> {
        val file = when (layer) {
            "tcp" -> ModulePaths.TCP_INI
            "udp" -> ModulePaths.UDP_INI
            else -> ModulePaths.STUN_INI
        }
        val content = sh("cat $file").stdout
        val items = mutableListOf(StrategyItem("", "<пусто>"))
        var currentId = ""
        content.lineSequence().forEach { raw ->
            val line = raw.trim()
            when {
                line.startsWith("[") && line.endsWith("]") -> currentId = line.removePrefix("[").removeSuffix("]")
                line.startsWith("desc=") && currentId.isNotBlank() -> {
                    items += StrategyItem(currentId, line.removePrefix("desc="))
                    currentId = ""
                }
            }
        }
        return items.distinctBy { it.id }
    }

    fun listZapretProfiles(): List<ZapretProfileItem> {
        val out = sh("sh ${ModulePaths.SCRIPTS}/list_zapret_profiles.sh").stdout
        return out.lineSequence()
            .map { it.trim() }
            .filter { it.isNotBlank() }
            .mapNotNull { line ->
                val parts = line.split("|").map { it.trim() }
                if (parts.size < 2) return@mapNotNull null
                ZapretProfileItem(
                    id = parts[0],
                    name = parts[1],
                    summary = parts.drop(2).joinToString(" | ")
                )
            }
            .toList()
    }

    fun setZapretProfile(profileId: String): ShellResult =
        sh("sh ${ModulePaths.SCRIPTS}/set_zapret_profile.sh ${shellQuote(profileId)}")

    fun setServiceMode(serviceId: String, mode: String): ShellResult =
        sh("sh ${ModulePaths.SCRIPTS}/set_service_mode.sh ${shellQuote(serviceId)} ${shellQuote(mode)}")

    fun setServiceStrategy(serviceId: String, layer: String, strategyId: String): ShellResult =
        sh("sh ${ModulePaths.SCRIPTS}/set_service_strategy.sh ${shellQuote(serviceId)} ${shellQuote(layer)} ${shellQuote(strategyId)}")

    fun createService(name: String, mode: String, domainsRaw: String): ShellResult {
        val temp = File.createTempFile("zapret_service_", ".txt")
        temp.writeText(domainsRaw)
        val result = sh("sh ${ModulePaths.SCRIPTS}/create_service.sh ${shellQuote(name)} ${shellQuote(mode)} ${shellQuote(temp.absolutePath)}")
        temp.delete()
        return result
    }

    fun exportCustomServices(): ShellResult =
        sh("sh ${ModulePaths.SCRIPTS}/export_custom_services.sh")

    fun importCustomServices(payload: String): ShellResult {
        val temp = File.createTempFile("zapret_custom_services_", ".txt")
        temp.writeText(payload)
        val result = sh("sh ${ModulePaths.SCRIPTS}/import_custom_services.sh ${shellQuote(temp.absolutePath)}")
        temp.delete()
        return result
    }

    fun deleteService(serviceId: String): ShellResult =
        sh("sh ${ModulePaths.SCRIPTS}/delete_service.sh ${shellQuote(serviceId)}")

    fun applyServiceModes(): ShellResult = sh("sh ${ModulePaths.SCRIPTS}/apply_service_modes.sh")

    fun rebuildServiceIpsets(serviceId: String? = null, force: Boolean = false): ShellResult {
        val forceArg = if (force) " --force" else ""
        return if (serviceId.isNullOrBlank()) sh("sh ${ModulePaths.SCRIPTS}/rebuild_service_ipsets.sh$forceArg")
        else sh("sh ${ModulePaths.SCRIPTS}/rebuild_service_ipsets.sh ${shellQuote(serviceId)}$forceArg")
    }

    fun startAll(): ShellResult = sh("sh ${ModulePaths.SCRIPTS}/start_all.sh")

    fun stopAll(): ShellResult = sh("sh ${ModulePaths.SCRIPTS}/stop_all.sh")

    fun restartAll(): ShellResult {
        val stop = stopAll()
        val start = startAll()
        return ShellResult(
            code = if (start.code != 0) start.code else stop.code,
            stdout = listOf(stop.stdout, start.stdout).filter { it.isNotBlank() }.joinToString("\n"),
            stderr = listOf(stop.stderr, start.stderr).filter { it.isNotBlank() }.joinToString("\n")
        )
    }

    private fun sh(command: String): ShellResult = RootShell.run(command)

    private fun parseVarFile(text: String): Map<String, String> {
        return buildMap {
            text.lineSequence().forEach { raw ->
                val line = raw.trim()
                if (line.isBlank() || line.startsWith("#") || !line.contains('=')) return@forEach
                val idx = line.indexOf('=')
                val key = line.substring(0, idx)
                var value = line.substring(idx + 1).trim()
                value = value.removePrefix("\"").removeSuffix("\"")
                value = value.removePrefix("'").removeSuffix("'")
                put(key, value)
            }
        }
    }

    private fun shellQuote(value: String): String = "'" + value.replace("'", "'\\''") + "'"
}
