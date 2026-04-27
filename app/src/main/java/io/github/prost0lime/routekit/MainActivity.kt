package io.github.prost0lime.routekit

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Typeface
import android.net.Uri
import android.os.Bundle
import android.graphics.Color
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.view.View
import android.widget.ArrayAdapter
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.Spinner
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.google.android.material.slider.Slider
import com.google.android.material.switchmaterial.SwitchMaterial
import io.github.prost0lime.routekit.databinding.ActivityMainBinding
import io.github.prost0lime.routekit.databinding.DialogCustomServiceBinding
import io.github.prost0lime.routekit.databinding.DialogImportTextBinding
import io.github.prost0lime.routekit.databinding.DialogServiceModeBinding
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.suspendCancellableCoroutine
import java.io.File
import kotlin.coroutines.resume

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private val repo = ModuleRepository()
    private val servicesAdapter = ServicesAdapter(::onServiceModeQuickSet, ::onServiceConfigure, ::onServiceDiagnose, ::onServiceRepair, ::onDeleteService)
    private var tcpStrategies: List<StrategyItem> = emptyList()
    private var udpStrategies: List<StrategyItem> = emptyList()
    private var stunStrategies: List<StrategyItem> = emptyList()
    private var zapretProfiles: List<ZapretProfileItem> = emptyList()
    private lateinit var currentHealth: HealthStatus
    private var actionInProgress: Boolean = false
    private var vpnSectionExpanded: Boolean = true
    private var pendingApplyReason: String? = null
    private var currentProfiles: List<ProxyProfile> = emptyList()
    private var currentProfileGroups: Map<String, ProfileGroup> = emptyMap()
    private val expandedProfileGroups = mutableSetOf<String>()
    private val profilePingMsByGroup = mutableMapOf<String, Map<String, Int?>>()

    private val openTextFile = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) importFromPickedFile(uri)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
        vpnSectionExpanded = savedInstanceState?.getBoolean(KEY_VPN_SECTION_EXPANDED) ?: true
        pendingApplyReason = savedInstanceState?.getString(KEY_PENDING_APPLY_REASON)

        binding.rvServices.layoutManager = androidx.recyclerview.widget.LinearLayoutManager(this)
        binding.rvServices.adapter = servicesAdapter

        binding.btnRefresh.setOnClickListener { if (!actionInProgress) refreshAll() }
        binding.btnStartAll.setOnClickListener { startModulePipeline() }
        binding.btnStopAll.setOnClickListener { runAction("Выключение модуля", "Выключено", repo::stopAll) }
        binding.btnModuleSettings.setOnClickListener { showModuleSettingsDialog() }
        binding.btnCheckUpdates.setOnClickListener { checkForUpdates() }
        binding.btnAddService.setOnClickListener { showAddServiceDialog() }
        binding.btnImportCustomServices.setOnClickListener { showImportCustomServicesDialog() }
        binding.btnExportCustomServices.setOnClickListener { exportCustomServices() }
        binding.btnImportUrl.setOnClickListener { showImportUrlDialog() }
        binding.btnImportText.setOnClickListener { showImportTextDialog() }
        binding.btnImportFile.setOnClickListener { openTextFile.launch(arrayOf("text/plain", "text/*", "*/*")) }
        binding.swipeRefresh.setOnRefreshListener { if (!actionInProgress) refreshAll() else binding.swipeRefresh.isRefreshing = false }
        binding.layoutVpnHeader.setOnClickListener { toggleVpnSection() }

        applyVpnSectionState()
        setUiBusy(false)
        refreshAll()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putBoolean(KEY_VPN_SECTION_EXPANDED, vpnSectionExpanded)
        outState.putString(KEY_PENDING_APPLY_REASON, pendingApplyReason)
    }

    private fun refreshAll() {
        lifecycleScope.launch {
            binding.swipeRefresh.isRefreshing = true
            try {
                refreshData()
            } finally {
                binding.swipeRefresh.isRefreshing = false
            }
        }
    }

    private suspend fun refreshData() {
        currentHealth = withContext(Dispatchers.IO) { repo.healthcheckParsed() }
        val profiles = withContext(Dispatchers.IO) { repo.listProfiles() }
        val groups = withContext(Dispatchers.IO) { repo.listProfileGroups() }
        val services = withContext(Dispatchers.IO) { repo.listServices() }
        tcpStrategies = withContext(Dispatchers.IO) { repo.loadStrategies("tcp") }
        udpStrategies = withContext(Dispatchers.IO) { repo.loadStrategies("udp") }
        stunStrategies = withContext(Dispatchers.IO) { repo.loadStrategies("stun") }
        zapretProfiles = withContext(Dispatchers.IO) { repo.listZapretProfiles() }

        renderStatus(currentHealth)
        currentProfileGroups = groups.associateBy { it.id }
        renderProfiles(profiles)
        servicesAdapter.submitList(services)
        servicesAdapter.setActionsEnabled(!actionInProgress)
    }


    private fun renderProfiles(profiles: List<ProxyProfile>) {
        currentProfiles = profiles
        binding.containerProfiles.removeAllViews()
        if (profiles.isEmpty()) {
            val tv = android.widget.TextView(this).apply { text = "Профили не найдены" }
            binding.containerProfiles.addView(tv)
            return
        }

        val grouped = profiles.groupBy { profileGroupKey(it) }
        expandedProfileGroups.retainAll(grouped.keys)

        grouped.entries
            .sortedWith(compareByDescending<Map.Entry<String, List<ProxyProfile>>> { entry -> entry.value.any { it.isActive } }
                .thenBy { entry -> entry.value.firstOrNull()?.groupName.orEmpty() })
            .forEach { (groupKey, groupProfiles) ->
                renderProfileGroup(groupKey, groupProfiles)
            }
    }

    private fun renderProfileGroup(groupKey: String, profiles: List<ProxyProfile>) {
        val first = profiles.first()
        val expanded = expandedProfileGroups.contains(groupKey)
        val pingMap = profilePingMsByGroup[groupKey].orEmpty()
        val group = currentProfileGroups[groupKey]
        val sortedProfiles = if (pingMap.isNotEmpty()) {
            profiles.sortedWith(
                compareBy<ProxyProfile> { pingMap[it.id] ?: Int.MAX_VALUE }
                    .thenBy { it.name.lowercase() }
            )
        } else {
            profiles
        }

        val card = com.google.android.material.card.MaterialCardView(this).apply {
            layoutParams = android.widget.LinearLayout.LayoutParams(
                android.widget.LinearLayout.LayoutParams.MATCH_PARENT,
                android.widget.LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                bottomMargin = dp(10)
            }
        }
        val outer = android.widget.LinearLayout(this).apply {
            orientation = android.widget.LinearLayout.VERTICAL
            setPadding(dp(14), dp(14), dp(14), dp(14))
        }

        val header = android.widget.LinearLayout(this).apply {
            orientation = android.widget.LinearLayout.HORIZONTAL
            gravity = android.view.Gravity.CENTER_VERTICAL
        }
        val titleBlock = android.widget.LinearLayout(this).apply {
            orientation = android.widget.LinearLayout.VERTICAL
            layoutParams = android.widget.LinearLayout.LayoutParams(0, android.widget.LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        }
        val title = android.widget.TextView(this).apply {
            text = first.groupName.ifBlank { "Без группы" }
            textSize = 16f
            setTypeface(typeface, android.graphics.Typeface.BOLD)
        }
        val subtitle = android.widget.TextView(this).apply {
            val active = profiles.firstOrNull { it.isActive }?.name
            text = buildString {
                append("Профилей: ${profiles.size}")
                if (!active.isNullOrBlank()) append("  •  активен: $active")
                if (pingMap.isNotEmpty()) append("  •  пинг проверен")
            }
        }
        titleBlock.addView(title)
        titleBlock.addView(subtitle)

        val toggle = android.widget.TextView(this).apply {
            text = if (expanded) "Свернуть" else "Развернуть"
            setPadding(dp(10), dp(8), 0, dp(8))
        }
        header.addView(titleBlock)
        header.addView(toggle)
        header.setOnClickListener {
            if (actionInProgress) return@setOnClickListener
            if (expanded) expandedProfileGroups.remove(groupKey) else expandedProfileGroups.add(groupKey)
            renderProfiles(currentProfiles)
        }
        toggle.setOnClickListener {
            if (actionInProgress) return@setOnClickListener
            if (expanded) expandedProfileGroups.remove(groupKey) else expandedProfileGroups.add(groupKey)
            renderProfiles(currentProfiles)
        }

        outer.addView(header)
        if (groupKey != "__ungrouped") {
            val actions = android.widget.LinearLayout(this).apply {
                orientation = android.widget.LinearLayout.HORIZONTAL
                setPadding(0, dp(10), 0, 0)
            }
            val pingButton = com.google.android.material.button.MaterialButton(this).apply {
                text = "Пинг"
                minWidth = 0
                isEnabled = !actionInProgress
                setOnClickListener { if (!actionInProgress) pingProfileGroup(groupKey, first.groupName) }
                layoutParams = android.widget.LinearLayout.LayoutParams(0, android.widget.LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            }
            val updateButton = com.google.android.material.button.MaterialButton(this).apply {
                text = "Обновить"
                minWidth = 0
                isEnabled = !actionInProgress && group?.hasSourceUrl == true
                setOnClickListener { if (!actionInProgress) updateProfileGroup(groupKey, first.groupName) }
                layoutParams = android.widget.LinearLayout.LayoutParams(0, android.widget.LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                    marginStart = dp(8)
                }
            }
            val deleteButton = com.google.android.material.button.MaterialButton(this).apply {
                text = "Удалить"
                minWidth = 0
                isEnabled = !actionInProgress
                setOnClickListener { if (!actionInProgress) deleteProfileGroup(groupKey, first.groupName) }
                layoutParams = android.widget.LinearLayout.LayoutParams(0, android.widget.LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                    marginStart = dp(8)
                }
            }
            actions.addView(pingButton)
            actions.addView(updateButton)
            actions.addView(deleteButton)
            outer.addView(actions)
        }
        if (expanded) {
            sortedProfiles.forEach { item ->
                val itemBinding = io.github.prost0lime.routekit.databinding.ItemProfileBinding.inflate(layoutInflater, outer, false)
                itemBinding.tvProfileName.text = item.name
                val pingText = when {
                    !pingMap.containsKey(item.id) -> ""
                    pingMap[item.id] == null -> "  •  ping: timeout"
                    else -> "  •  ping: ${pingMap[item.id]} ms"
                }
                itemBinding.tvProfileMeta.text = "${item.serverMeta}$pingText"
                itemBinding.tvProfileId.text = item.id
                itemBinding.tvProfileActive.visibility = if (item.isActive) View.VISIBLE else View.GONE
                itemBinding.btnActivate.isEnabled = !item.isActive && !actionInProgress
                itemBinding.btnDiagnose.isEnabled = !actionInProgress
                itemBinding.btnDelete.isEnabled = !actionInProgress
                itemBinding.btnActivate.text = if (item.isActive) "Активен" else "Выбрать"
                itemBinding.btnActivate.setOnClickListener { if (!actionInProgress) onProfileActivate(item) }
                itemBinding.btnDiagnose.setOnClickListener { if (!actionInProgress) onProfileDiagnose(item) }
                itemBinding.btnDelete.setOnClickListener { if (!actionInProgress) onProfileDelete(item) }
                outer.addView(itemBinding.root)
            }
        }
        card.addView(outer)
        binding.containerProfiles.addView(card)
    }

    private fun profileGroupKey(profile: ProxyProfile): String =
        if (profile.groupId.isBlank() || profile.groupId == "-") "__ungrouped" else profile.groupId

    private fun pingProfileGroup(groupKey: String, groupName: String) {
        guardedAction("Проверка ping", groupName.ifBlank { "VPN группа" }) {
            val results = withContext(Dispatchers.IO) { repo.pingProfileGroup(groupKey) }
            profilePingMsByGroup[groupKey] = results.associate { it.profileId to it.pingMs }
            expandedProfileGroups.add(groupKey)
            val okCount = results.count { it.pingMs != null }
            toast("Ping: $okCount/${results.size} профилей ответили")
            setUiBusy(false, "Готово", "Ping профилей обновлён")
        }
    }

    private fun updateProfileGroup(groupKey: String, groupName: String) {
        guardedAction("Обновление VPN-группы", groupName.ifBlank { groupKey }) {
            val result = withContext(Dispatchers.IO) { repo.updateProfileGroup(groupKey) }
            if (result.code == 0) {
                profilePingMsByGroup.remove(groupKey)
                setUiBusy(true, "Обновление VPN-группы", "Обновление статуса")
                refreshData()
                toast("VPN-группа обновлена")
                setUiBusy(false, "Готово", "Профили обновлены из сохранённой ссылки")
            } else {
                showOutput("Не удалось обновить VPN-группу", result)
            }
        }
    }

    private fun deleteProfileGroup(groupKey: String, groupName: String) {
        AlertDialog.Builder(this)
            .setTitle("Удалить группу VPN?")
            .setMessage("${groupName.ifBlank { groupKey }}\nБудут удалены все профили внутри группы.")
            .setNegativeButton("Отмена", null)
            .setPositiveButton("Удалить") { _, _ ->
                guardedAction("Удаление VPN-группы", groupName.ifBlank { groupKey }) {
                    val result = withContext(Dispatchers.IO) { repo.deleteProfileGroup(groupKey) }
                    if (result.code == 0) {
                        expandedProfileGroups.remove(groupKey)
                        profilePingMsByGroup.remove(groupKey)
                        setUiBusy(true, "Удаление VPN-группы", "Обновление статуса")
                        refreshData()
                        toast("VPN-группа удалена")
                        setUiBusy(false, "Готово", "Группа и профили удалены")
                    } else {
                        showOutput("Не удалось удалить VPN-группу", result)
                    }
                }
            }
            .show()
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    private fun toggleVpnSection() {
        vpnSectionExpanded = !vpnSectionExpanded
        applyVpnSectionState()
    }

    private fun applyVpnSectionState() {
        binding.layoutVpnContent.visibility = if (vpnSectionExpanded) View.VISIBLE else View.GONE
        binding.tvVpnToggle.text = if (vpnSectionExpanded) "Свернуть" else "Развернуть"
    }

    private fun statusColor(value: String): Int = when (value.lowercase()) {
        "running", "enabled", "ok", "true" -> Color.parseColor("#146C2E")
        "stopped", "disabled", "failed", "error", "false" -> Color.parseColor("#B3261E")
        else -> Color.parseColor("#6B7280")
    }

    private fun appendStatusLine(builder: SpannableStringBuilder, label: String, value: String) {
        builder.append(label)
        val start = builder.length
        builder.append(value)
        builder.setSpan(ForegroundColorSpan(statusColor(value)), start, builder.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
    }

    private fun renderStatus(status: HealthStatus) {
        val vpnCount = status.serviceVpnCount.toIntOrNull() ?: 0
        val autoIpv4Count = status.autoIpsetTotal.toIntOrNull() ?: 0
        val proxyRunning = status.proxy == "running"
        val transproxyEnabled = status.transproxy == "enabled"
        val hasActiveProfile = status.activeProfileId.isNotBlank() && status.activeProfileId != "none"

        binding.tvSummary.text = SpannableStringBuilder().apply {
            appendStatusLine(this, "Zapret: ", status.zapret)
            append("  •  ")
            appendStatusLine(this, "Proxy: ", status.proxy)
            append("  •  ")
            appendStatusLine(this, "Transproxy: ", status.transproxy)
            append("\n")
            appendStatusLine(this, "Интернет: ", status.internet)
            append("  •  VPN-профиль: ${status.activeProfileName.ifBlank { "—" }}\n")
            append("Сервисы → Zapret: ${status.serviceZapretCount}, VPN: ${status.serviceVpnCount}, Direct: ${status.serviceDirectCount}, Custom: ${status.customServiceCount}")
        }

        binding.tvStatusMeta.text = buildString {
            append("Сервер: ${status.activeProfileServer.ifBlank { "—" }} | Группа: ${status.activeProfileGroup.ifBlank { "—" }}\n")
            append("Домены proxy/direct: ${status.proxyDomainsCount}/${status.directDomainsCount} | Auto IPv4: ${status.autoIpsetTotal} | Auto IPv6: ${status.autoIpv6IpsetTotal}\n")
            append("IPv6 block: ${status.ipv6Block} | DNS redirect: ${status.dnsRedirect} | Время: ${status.timestamp.ifBlank { "—" }}")
        }
        binding.btnStartAll.text = if (pendingApplyReason != null || proxyRunning || transproxyEnabled || status.zapret == "running") "Применить" else "Включить"

        binding.tvRawStatus.text = ""
        binding.tvRawStatus.visibility = View.GONE
        if (!actionInProgress) {
            val idleTitle = when {
                pendingApplyReason != null -> "Нужно применить"
                vpnCount > 0 && !hasActiveProfile -> "Нужен VPN-профиль"
                vpnCount > 0 && autoIpv4Count == 0 -> "Нужно собрать IP"
                vpnCount > 0 && proxyRunning && !transproxyEnabled -> "VPN не применён"
                vpnCount > 0 && transproxyEnabled && !proxyRunning -> "Proxy не запущен"
                vpnCount > 0 && proxyRunning && transproxyEnabled && status.dnsRedirect != "enabled" -> "DNS не применён"
                proxyRunning && transproxyEnabled -> "Включено"
                status.zapret == "running" -> "Частично включено"
                else -> "Выключено"
            }
            val idleDetail = when {
                pendingApplyReason != null -> "${pendingApplyReason}. Нажми Применить, чтобы обновить правила"
                vpnCount > 0 && !hasActiveProfile -> "Выбери профиль в блоке VPN и нажми Применить"
                vpnCount > 0 && autoIpv4Count == 0 -> "Для VPN-сервисов нет IPv4-правил: нажми Применить или пересобери IP"
                vpnCount > 0 && proxyRunning && !transproxyEnabled -> "Прокси запущен, но transproxy-правила ещё не активны"
                vpnCount > 0 && transproxyEnabled && !proxyRunning -> "Правила есть, но sing-box не слушает локальный proxy"
                vpnCount > 0 && proxyRunning && transproxyEnabled && status.dnsRedirect != "enabled" -> "VPN работает, но DNS redirect выключен"
                proxyRunning && transproxyEnabled -> "Прокси, DNS и маршрутизация активны"
                status.zapret == "running" -> "Работает только часть компонентов"
                else -> "Модуль не запущен"
            }
            setUiBusy(false, idleTitle, idleDetail)
        }
    }

    private fun runAction(title: String, successState: String, action: () -> ShellResult) {
        guardedAction(title, "Выполняется системный скрипт") {
            val result = withContext(Dispatchers.IO) { action() }
            if (result.code == 0) {
                setUiBusy(true, title, "Обновление статуса")
                refreshData()
                toast("$title выполнено")
                setUiBusy(false, successState, "Операция завершена")
            } else {
                showOutput(title, result)
            }
        }
    }

    private fun rebuildIpsets(serviceId: String? = null) {
        guardedAction("Пересборка IP", if (serviceId.isNullOrBlank()) "Пересчёт для всех сервисов" else "Пересчёт для $serviceId") {
            val result = withContext(Dispatchers.IO) { repo.rebuildServiceIpsets(serviceId, force = true) }
            if (result.code == 0) {
                setUiBusy(true, "Пересборка IP", "Обновление статуса")
                refreshData()
                toast(if (serviceId.isNullOrBlank()) "IP-списки пересобраны" else "IP-списки пересобраны для $serviceId")
                setUiBusy(false, "Готово", "IP-списки обновлены")
            } else {
                showOutput("Не удалось пересобрать IP-списки", result)
            }
        }
    }

    private fun startModulePipeline() {
        guardedAction("Применение режимов", "Подготовка конфигурации") {
            val apply = withContext(Dispatchers.IO) { repo.applyServiceModes() }
            if (apply.code != 0) {
                showOutput("Не удалось применить режимы сервисов", apply)
                return@guardedAction
            }
            pendingApplyReason = null
            setUiBusy(true, "Обновление", "Получение состояния модуля")
            refreshData()
            toast("Модуль включён")
            setUiBusy(false, "Включено", "Режимы применены и сервисы запущены")
        }
    }

    private fun guardedAction(title: String, detail: String, block: suspend () -> Unit) {
        if (actionInProgress) {
            toast("Дождись завершения текущей операции")
            return
        }
        lifecycleScope.launch {
            actionInProgress = true
            setUiBusy(true, title, detail)
            if (currentProfiles.isNotEmpty()) {
                renderProfiles(currentProfiles)
            }
            try {
                block()
            } finally {
                actionInProgress = false
                if (currentProfiles.isNotEmpty()) {
                    renderProfiles(currentProfiles)
                }
                servicesAdapter.setActionsEnabled(true)
                binding.swipeRefresh.isEnabled = true
                if (!binding.tvOperationState.text.contains("Включено") && !binding.tvOperationState.text.contains("Выключено") && !binding.tvOperationState.text.contains("Готово") && ::currentHealth.isInitialized) {
                    renderStatus(currentHealth)
                } else if (!::currentHealth.isInitialized) {
                    setUiBusy(false)
                }
            }
        }
    }

    private fun setUiBusy(busy: Boolean, title: String = "Готово", detail: String = "Можно выполнять действия") {
        binding.progressOperation.visibility = if (busy) android.view.View.VISIBLE else android.view.View.GONE
        binding.tvOperationState.text = title
        binding.tvOperationDetail.text = detail
        val enabled = !busy
        binding.swipeRefresh.isEnabled = enabled
        listOf(
            binding.btnRefresh,
            binding.btnStartAll,
            binding.btnStopAll,
            binding.btnImportUrl,
            binding.btnImportText,
            binding.btnImportFile,
            binding.btnAddService,
            binding.btnImportCustomServices,
            binding.btnExportCustomServices,
            binding.btnModuleSettings,
            binding.btnCheckUpdates
        ).forEach { it.isEnabled = enabled }
        servicesAdapter.setActionsEnabled(enabled)
        binding.containerProfiles.isEnabled = enabled
        binding.rvServices.isEnabled = enabled
    }

    private fun checkForUpdates() {
        guardedAction("Проверка обновлений", "Запрос GitHub Releases") {
            val moduleVersion = withContext(Dispatchers.IO) { repo.moduleVersion() }.ifBlank { "unknown" }
            val latest = try {
                withContext(Dispatchers.IO) { repo.fetchLatestRelease() }
            } catch (t: Throwable) {
                binding.tvUpdateStatus.text = "Не удалось проверить обновления: ${t.message ?: "unknown error"}"
                setUiBusy(false, "Ошибка обновления", "GitHub Releases недоступен")
                AlertDialog.Builder(this@MainActivity)
                    .setTitle("Не удалось проверить обновления")
                    .setMessage(t.message ?: t.toString())
                    .setPositiveButton("OK", null)
                    .show()
                return@guardedAction
            }
            val currentAppVersion = BuildConfig.VERSION_NAME
            val hasUpdate = compareVersions(latest.version, currentAppVersion) > 0 ||
                (moduleVersion != "unknown" && compareVersions(latest.version, moduleVersion) > 0)

            binding.tvUpdateStatus.text = buildString {
                append("APK: $currentAppVersion")
                append("  •  модуль: $moduleVersion")
                append("  •  latest: ${latest.tag.ifBlank { latest.version }}")
            }
            setUiBusy(false, if (hasUpdate) "Есть обновление" else "Обновлений нет", "Latest release: ${latest.tag.ifBlank { latest.version }}")

            val message = buildString {
                append("Текущая APK: $currentAppVersion\n")
                append("Текущий модуль: $moduleVersion\n")
                append("GitHub release: ${latest.tag.ifBlank { latest.version }}\n\n")
                if (hasUpdate) append("Доступна новая версия. Открой релиз и скачай APK/модуль вручную.\n")
                else append("Установленная версия выглядит актуальной.\n")
                if (!latest.apkUrl.isNullOrBlank()) append("\nAPK: ${latest.apkUrl}")
                if (!latest.moduleUrl.isNullOrBlank()) append("\nModule: ${latest.moduleUrl}")
            }

            AlertDialog.Builder(this@MainActivity)
                .setTitle(if (hasUpdate) "Доступно обновление" else "Обновлений нет")
                .setMessage(message)
                .setNegativeButton("Закрыть", null)
                .setNeutralButton("Копировать") { _, _ ->
                    copyToClipboard("RouteKit release", latest.releaseUrl)
                    toast("Ссылка скопирована")
                }
                .setPositiveButton("Открыть релиз") { _, _ -> openUrl(latest.releaseUrl) }
                .show()
        }
    }

    private fun showModuleSettingsDialog() {
        if (actionInProgress) {
            toast("Дождись завершения текущей операции")
            return
        }
        lifecycleScope.launch {
            val settings = withContext(Dispatchers.IO) { repo.loadModuleSettings() }
            val container = android.widget.LinearLayout(this@MainActivity).apply {
                orientation = android.widget.LinearLayout.VERTICAL
                setPadding(dp(8), dp(4), dp(8), dp(4))
            }
            val intro = TextView(this@MainActivity).apply {
                text = "Эти параметры влияют на сбор IP для VPN-сервисов и на IPv6-блокировку. После изменения нажми «Применить», чтобы пересобрать правила."
                textSize = 14f
            }
            val collectIpv6 = SwitchMaterial(this@MainActivity).apply {
                text = "Собирать IPv6/AAAA для диагностики"
                isChecked = settings.collectIpv6
            }
            val blockIpv6 = SwitchMaterial(this@MainActivity).apply {
                text = "Блокировать IPv6 на устройстве"
                isChecked = settings.ipv6BlockEnabled
            }
            val repeatLabel = TextView(this@MainActivity).apply {
                textSize = 14f
                setPadding(0, dp(12), 0, 0)
            }
            val repeatSlider = Slider(this@MainActivity).apply {
                valueFrom = 1f
                valueTo = 10f
                stepSize = 1f
                value = settings.dnsResolveRepeat.coerceIn(1, 10).toFloat()
            }
            fun updateRepeatLabel() {
                repeatLabel.text = "Повторы DNS-запросов при сборе доменов: ${repeatSlider.value.toInt()}"
            }
            repeatSlider.addOnChangeListener { _, _, _ -> updateRepeatLabel() }
            updateRepeatLabel()

            container.addView(intro)
            container.addView(collectIpv6)
            container.addView(blockIpv6)
            container.addView(repeatLabel)
            container.addView(repeatSlider)

            val dialog = AlertDialog.Builder(this@MainActivity)
                .setTitle("Настройки модуля")
                .setView(container)
                .setNeutralButton("Пояснение", null)
                .setNegativeButton("Отмена", null)
                .setPositiveButton("Сохранить", null)
                .show()

            dialog.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener {
                AlertDialog.Builder(this@MainActivity)
                    .setTitle("Что это значит")
                    .setMessage(
                        "IPv6 сейчас не проксируется через transproxy: правила прозрачного прокси работают по IPv4. Поэтому IPv6 обычно либо блокируется, либо используется только как диагностический сигнал.\n\n" +
                            "Повторы DNS помогают собрать больше CDN-IP для доменов вроде Cloudflare/LiveKit/Google. Чем выше число, тем полнее покрытие, но тем дольше пересборка IP."
                    )
                    .setPositiveButton("OK", null)
                    .show()
            }
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val next = ModuleSettings(
                    collectIpv6 = collectIpv6.isChecked,
                    dnsResolveRepeat = repeatSlider.value.toInt().coerceIn(1, 10),
                    ipv6BlockEnabled = blockIpv6.isChecked
                )
                dialog.dismiss()
                guardedAction("Сохранение настроек", "Обновление поведения модуля") {
                    val result = withContext(Dispatchers.IO) { repo.saveModuleSettings(next) }
                    if (result.code == 0) {
                        pendingApplyReason = "Настройки модуля изменены"
                        setUiBusy(true, "Сохранение настроек", "Обновление статуса")
                        refreshData()
                        toast("Настройки сохранены")
                        setUiBusy(false, "Нужно применить", "Нажми Применить, чтобы пересобрать правила")
                    } else {
                        showOutput("Не удалось сохранить настройки", result)
                    }
                }
            }
        }
    }

    private fun showAddServiceDialog() {
        if (actionInProgress) {
            toast("Дождись завершения текущей операции")
            return
        }
        val dialogBinding = DialogCustomServiceBinding.inflate(layoutInflater)
        dialogBinding.spinnerMode.adapter = ArrayAdapter(
            this,
            android.R.layout.simple_spinner_dropdown_item,
            listOf("vpn", "zapret", "direct")
        )
        val dialog = AlertDialog.Builder(this)
            .setTitle("Новый сервис")
            .setView(dialogBinding.root)
            .setNegativeButton("Отмена", null)
            .setPositiveButton("Создать", null)
            .show()

        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val name = dialogBinding.etServiceName.text?.toString()?.trim().orEmpty()
                val domains = dialogBinding.etDomains.text?.toString().orEmpty()
                val mode = dialogBinding.spinnerMode.selectedItem?.toString().orEmpty().ifBlank { "direct" }
                if (name.isBlank()) {
                    toast("Укажи название сервиса")
                    return@setOnClickListener
                }
                if (mode == "vpn" && !hasDomainEntries(domains)) {
                    toast("Для VPN-сервиса нужны домены")
                    return@setOnClickListener
                }
                proceedWithVpnProfileWarning(mode, "VPN-сервис будет создан, но без активного VPN-профиля он не заработает.") {
                    dialog.dismiss()
                    guardedAction("Создание сервиса", name) {
                        val result = withContext(Dispatchers.IO) { repo.createService(name, mode, domains) }
                        if (result.code == 0) {
                            pendingApplyReason = "Создан сервис ${result.stdout.ifBlank { name }}"
                            setUiBusy(true, "Создание сервиса", "Обновление статуса")
                            toast("Сервис создан: ${result.stdout.ifBlank { name }}")
                            refreshData()
                            setUiBusy(false, "Нужно применить", "Нажми Применить, чтобы обновить правила")
                        } else {
                            showOutput("Не удалось создать сервис", result)
                        }
                    }
                }
            }
    }

    private fun onDeleteService(service: ServiceItem) {
        if (!service.isCustom) {
            toast("Удалять можно только пользовательские сервисы")
            return
        }
        AlertDialog.Builder(this)
            .setTitle("Удалить сервис?")
            .setMessage("${service.name}\n${service.id}")
            .setNegativeButton("Отмена", null)
            .setPositiveButton("Удалить") { _, _ ->
                guardedAction("Удаление сервиса", service.name) {
                    val result = withContext(Dispatchers.IO) { repo.deleteService(service.id) }
                    if (result.code == 0) {
                        pendingApplyReason = "Удалён сервис ${service.name}"
                        setUiBusy(true, "Удаление сервиса", "Обновление статуса")
                        toast("Сервис удалён")
                        refreshData()
                        setUiBusy(false, "Нужно применить", "Нажми Применить, чтобы убрать старые правила")
                    } else {
                        showOutput("Не удалось удалить сервис", result)
                    }
                }
            }
            .show()
    }

    private fun showImportUrlDialog() {
        if (actionInProgress) {
            toast("Дождись завершения текущей операции")
            return
        }
        val dialogBinding = DialogImportTextBinding.inflate(layoutInflater)
        dialogBinding.tilPrimary.hint = "Ссылка подписки"
        dialogBinding.etPrimary.setSingleLine(false)
        dialogBinding.etPrimary.setText("")

        AlertDialog.Builder(this)
            .setTitle("Импорт по ссылке")
            .setView(dialogBinding.root)
            .setNegativeButton("Отмена", null)
            .setPositiveButton("Импорт") { _, _ ->
                val url = dialogBinding.etPrimary.text?.toString()?.trim().orEmpty()
                val groupName = dialogBinding.etSecondary.text?.toString()?.trim().orEmpty().ifBlank { null }
                if (url.isBlank()) {
                    toast("Вставь ссылку подписки")
                    return@setPositiveButton
                }
                lifecycleScope.launch {
                    val result = withContext(Dispatchers.IO) { repo.importSubscription(url, groupName) }
                    if (result.code == 0) {
                        toast("Подписка импортирована")
                        refreshAll()
                    } else {
                        showOutput("Ошибка импорта по ссылке", result)
                    }
                }
            }
            .show()
    }

    private fun showImportTextDialog(prefill: String = "") {
        if (actionInProgress) {
            toast("Дождись завершения текущей операции")
            return
        }
        val dialogBinding = DialogImportTextBinding.inflate(layoutInflater)
        dialogBinding.tilPrimary.hint = "Один VLESS, несколько VLESS или содержимое txt"
        dialogBinding.etPrimary.setText(prefill)

        AlertDialog.Builder(this)
            .setTitle("Импорт VLESS / TXT")
            .setView(dialogBinding.root)
            .setNegativeButton("Отмена", null)
            .setPositiveButton("Импорт") { _, _ ->
                val content = dialogBinding.etPrimary.text?.toString().orEmpty()
                val name = dialogBinding.etSecondary.text?.toString()?.trim().orEmpty().ifBlank { null }
                if (content.isBlank()) {
                    toast("Вставь содержимое")
                    return@setPositiveButton
                }
                importRawContent(content, name)
            }
            .show()
    }

    private fun showImportCustomServicesDialog(prefill: String = "") {
        if (actionInProgress) {
            toast("Дождись завершения текущей операции")
            return
        }
        val dialogBinding = DialogImportTextBinding.inflate(layoutInflater)
        dialogBinding.tilPrimary.hint = null
        dialogBinding.tilPrimary.helperText = "Вставь текст, полученный через экспорт кастомных сервисов"
        dialogBinding.etPrimary.setText(prefill)
        dialogBinding.etPrimary.hint = "BEGIN_SERVICE\nservice_name=4pda\nmode=vpn\ndomain=4pda.to\nEND_SERVICE"
        dialogBinding.etPrimary.minLines = 8
        dialogBinding.tilSecondary.visibility = View.GONE

        val dialog = AlertDialog.Builder(this)
            .setTitle("Импорт кастомных сервисов")
            .setView(dialogBinding.root)
            .setNegativeButton("Отмена", null)
            .setNeutralButton("Вставить", null)
            .setPositiveButton("Импорт", null)
            .show()

        dialog.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener {
            val clipboardText = readClipboardText()
            if (clipboardText.isBlank()) {
                toast("Буфер обмена пуст")
            } else {
                dialogBinding.etPrimary.setText(clipboardText)
                dialogBinding.etPrimary.setSelection(dialogBinding.etPrimary.text?.length ?: 0)
            }
        }
        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val payload = dialogBinding.etPrimary.text?.toString().orEmpty()
                if (payload.isBlank()) {
                    toast("Вставь экспорт кастомных сервисов")
                    return@setOnClickListener
                }
                dialog.dismiss()
                guardedAction("Импорт сервисов", "Добавление кастомных сервисов") {
                    val result = withContext(Dispatchers.IO) { repo.importCustomServices(payload) }
                    if (result.code == 0) {
                        pendingApplyReason = "Импортированы кастомные сервисы"
                        setUiBusy(true, "Импорт сервисов", "Обновление статуса")
                        refreshData()
                        toast("Кастомные сервисы импортированы")
                        setUiBusy(false, "Нужно применить", "Нажми Применить, чтобы обновить правила")
                    } else {
                        showOutput("Не удалось импортировать кастомные сервисы", result)
                    }
                }
        }
    }

    private fun exportCustomServices() {
        guardedAction("Экспорт сервисов", "Подготовка экспорта") {
            val result = withContext(Dispatchers.IO) { repo.exportCustomServices() }
            if (result.code != 0) {
                showOutput("Не удалось экспортировать кастомные сервисы", result)
                return@guardedAction
            }

            val dialogBinding = DialogImportTextBinding.inflate(layoutInflater)
            dialogBinding.tilPrimary.hint = null
            dialogBinding.tilPrimary.helperText = "Сохрани этот текст или вставь его на другом устройстве через импорт"
            dialogBinding.etPrimary.setText(result.stdout.trim())
            dialogBinding.etPrimary.minLines = 8
            dialogBinding.tilSecondary.visibility = View.GONE

            withContext(Dispatchers.Main) {
                val dialog = AlertDialog.Builder(this@MainActivity)
                    .setTitle("Экспорт кастомных сервисов")
                    .setView(dialogBinding.root)
                    .setNeutralButton("Копировать", null)
                    .setPositiveButton("Закрыть", null)
                    .show()

                dialog.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener {
                    copyToClipboard("custom_services_export", dialogBinding.etPrimary.text?.toString().orEmpty())
                    toast("Экспорт скопирован")
                }
            }

            setUiBusy(false, "Готово", "Экспорт подготовлен")
        }
    }

    private fun importRawContent(content: String, name: String?) {
        guardedAction("Импорт профилей", "Обработка ссылки или текста") {
            val result = withContext(Dispatchers.IO) {
                val cleaned = content.trim()
                val lines = cleaned.lines().map { it.trim() }.filter { it.isNotBlank() }
                when {
                    lines.size == 1 && lines.first().startsWith("http") -> repo.importSubscription(lines.first(), name)
                    lines.size == 1 && lines.first().startsWith("vless://") -> repo.importVless(lines.first(), name)
                    else -> {
                        val temp = File.createTempFile("zapret_import_", ".txt", cacheDir)
                        temp.writeText(cleaned)
                        repo.importGroupFile(temp.absolutePath, name)
                    }
                }
            }
            if (result.code == 0) {
                setUiBusy(true, "Импорт профилей", "Обновление статуса")
                toast("Импорт выполнен")
                refreshData()
                setUiBusy(false, "Готово", "Импорт завершён")
            } else {
                showOutput("Ошибка импорта", result)
            }
        }
    }

    private fun importFromPickedFile(uri: Uri) {
        lifecycleScope.launch {
            val content = withContext(Dispatchers.IO) { readTextFromUri(this@MainActivity, uri) }
            if (content.isBlank()) {
                toast("Не удалось прочитать файл")
                return@launch
            }
            showImportTextDialog(content)
        }
    }

    private fun onProfileActivate(profile: ProxyProfile) {
        guardedAction("Выбор VPN-профиля", profile.name) {
            val result = withContext(Dispatchers.IO) { repo.setActiveProfile(profile.id) }
            if (result.code == 0) {
                setUiBusy(true, "Выбор VPN-профиля", "Обновление статуса")
                toast("Активный профиль: ${profile.name}")
                refreshData()
                setUiBusy(false, "Готово", "Активный профиль обновлён")
            } else {
                showOutput("Не удалось выбрать профиль", result)
            }
        }
    }

    private fun onProfileDiagnose(profile: ProxyProfile) {
        if (actionInProgress) {
            toast("Дождись завершения текущей операции")
            return
        }
        lifecycleScope.launch {
            val result = withContext(Dispatchers.IO) { repo.diagnoseProfile(profile.id) }
            if (result.code == 0) {
                val report = result.stdout.ifBlank { "<empty>" }
                val textView = TextView(this@MainActivity).apply {
                    text = report
                    textSize = 12f
                    typeface = Typeface.MONOSPACE
                    setTextIsSelectable(true)
                    setPadding(24, 16, 24, 16)
                }
                val scrollView = ScrollView(this@MainActivity).apply {
                    addView(textView)
                }
                AlertDialog.Builder(this@MainActivity)
                    .setTitle("Диагностика профиля: ${profile.name}")
                    .setView(scrollView)
                    .setNeutralButton("Копировать", null)
                    .setPositiveButton("OK", null)
                    .show()
                    .also { dialog ->
                        dialog.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener {
                            copyToClipboard("profile_diagnostics_${profile.id}", report)
                            toast("Диагностика скопирована")
                        }
                    }
            } else {
                showOutput("Не удалось выполнить диагностику профиля", result)
            }
        }
    }

    private fun onProfileDelete(profile: ProxyProfile) {
        AlertDialog.Builder(this)
            .setTitle("Удалить профиль?")
            .setMessage("${profile.name}\n${profile.id}")
            .setNegativeButton("Отмена", null)
            .setPositiveButton("Удалить") { _, _ ->
                guardedAction("Удаление профиля", profile.name) {
                    val result = withContext(Dispatchers.IO) { repo.deleteProfile(profile.id) }
                    if (result.code == 0) {
                        setUiBusy(true, "Удаление профиля", "Обновление статуса")
                        toast("Профиль удалён")
                        refreshData()
                        setUiBusy(false, "Готово", "Профиль удалён")
                    } else {
                        showOutput("Не удалось удалить профиль", result)
                    }
                }
            }
            .show()
    }

    private fun onServiceModeQuickSet(service: ServiceItem, mode: String) {
        if (mode == "vpn" && service.domainCount == 0) {
            toast("Для VPN-сервиса нужны домены")
            return
        }
        proceedWithVpnProfileWarning(mode, "Режим VPN сохранится, но без активного VPN-профиля сервис не заработает.") {
            guardedAction("Смена режима", "${service.name} → ${mode.uppercase()}") {
                val result = withContext(Dispatchers.IO) { repo.setServiceMode(service.id, mode) }
                if (result.code == 0) {
                    pendingApplyReason = "Режим сервиса ${service.name} изменён"
                    setUiBusy(true, "Смена режима", "Обновление статуса")
                    toast("${service.name}: режим $mode сохранён")
                    refreshData()
                    setUiBusy(false, "Нужно применить", "Нажми Применить, чтобы обновить правила")
                } else {
                    showOutput("Не удалось изменить режим сервиса", result)
                }
            }
        }
    }

    private fun onServiceConfigure(service: ServiceItem) {
        if (actionInProgress) {
            toast("Дождись завершения текущей операции")
            return
        }
        lifecycleScope.launch {
            val details = withContext(Dispatchers.IO) { repo.getServiceDetails(service.id) }
            val domains = withContext(Dispatchers.IO) { repo.loadServiceDomains(service.id) }
            val coverage = withContext(Dispatchers.IO) { repo.getServiceCoverage(service.id) }
            showServiceDialog(service, details, domains, coverage)
        }
    }

    private fun showServiceDialog(
        service: ServiceItem,
        details: ServiceDetails,
        domainsText: String,
        coverage: ServiceCoverage
    ) {
        val dialogBinding = DialogServiceModeBinding.inflate(layoutInflater)

        dialogBinding.spinnerTcp.adapter = ArrayAdapter(this, android.R.layout.simple_spinner_dropdown_item, tcpStrategies)
        dialogBinding.spinnerUdp.adapter = ArrayAdapter(this, android.R.layout.simple_spinner_dropdown_item, udpStrategies)
        dialogBinding.spinnerStun.adapter = ArrayAdapter(this, android.R.layout.simple_spinner_dropdown_item, stunStrategies)

        selectStrategy(dialogBinding.spinnerTcp, tcpStrategies, details.tcpStrategy)
        selectStrategy(dialogBinding.spinnerUdp, udpStrategies, details.udpStrategy)
        selectStrategy(dialogBinding.spinnerStun, stunStrategies, details.stunStrategy)

        when (details.mode) {
            "zapret" -> dialogBinding.rbZapret.isChecked = true
            "vpn" -> dialogBinding.rbVpn.isChecked = true
            else -> dialogBinding.rbDirect.isChecked = true
        }
        dialogBinding.etDomains.setText(domainsText.trim())
        dialogBinding.tvCoverage.text = buildString {
            append("Домены: ${coverage.domainCount} | auto IPv4: ${coverage.autoIpCount} | auto IPv6: ${coverage.autoIpv6Count} | всего IPv4 IP: ${coverage.totalIpCount}\n")
            append("Coverage: ${coverage.coverageStatus} | ipv6: ${coverage.ipv6Status} | unresolved: ${coverage.unresolvedCount} | conflicts: ${coverage.conflictCount}")
            if (coverage.modeConflictCount > 0) {
                append("\nКонфликты режимов: ${coverage.modeConflictCount}")
            }
            append("\nstatic TCP: ${coverage.tcpStaticCount} | static UDP: ${coverage.udpStaticCount} | static STUN: ${coverage.stunStaticCount}")
            append("\n\nIP, unresolved и конфликты смотри в диагностике.")
        }
        toggleStrategies(dialogBinding, details.mode)

        dialogBinding.rgMode.setOnCheckedChangeListener { _: RadioGroup, checkedId: Int ->
            val mode = when (checkedId) {
                dialogBinding.rbZapret.id -> "zapret"
                dialogBinding.rbVpn.id -> "vpn"
                else -> "direct"
            }
            toggleStrategies(dialogBinding, mode)
        }

        dialogBinding.btnValidateDomains.setOnClickListener {
            lifecycleScope.launch {
                val validation = withContext(Dispatchers.IO) {
                    repo.validateServiceDomains(service.id, dialogBinding.etDomains.text?.toString().orEmpty())
                }
                showValidationDialog("Проверка доменов", validation)
            }
        }
        dialogBinding.btnShowDiagnostics.setOnClickListener {
            onServiceDiagnose(service)
        }

        AlertDialog.Builder(this)
            .setTitle(service.name)
            .setView(dialogBinding.root)
            .setNegativeButton("Отмена", null)
            .setPositiveButton("Сохранить") { _, _ ->
                val mode = when {
                    dialogBinding.rbZapret.isChecked -> "zapret"
                    dialogBinding.rbVpn.isChecked -> "vpn"
                    else -> "direct"
                }
                saveServiceChanges(
                    service.id,
                    details.mode,
                    details.tcpStrategy,
                    details.udpStrategy,
                    details.stunStrategy,
                    domainsText,
                    mode,
                    (dialogBinding.spinnerTcp.selectedItem as? StrategyItem)?.id.orEmpty(),
                    (dialogBinding.spinnerUdp.selectedItem as? StrategyItem)?.id.orEmpty(),
                    (dialogBinding.spinnerStun.selectedItem as? StrategyItem)?.id.orEmpty(),
                    dialogBinding.etDomains.text?.toString().orEmpty()
                )
            }
            .show()
    }

    private fun onServiceDiagnose(service: ServiceItem) {
        if (actionInProgress) {
            toast("Дождись завершения текущей операции")
            return
        }
        lifecycleScope.launch {
            val result = withContext(Dispatchers.IO) { repo.diagnoseService(service.id) }
            if (result.code == 0) {
                val report = result.stdout.ifBlank { "<empty>" }
                val textView = TextView(this@MainActivity).apply {
                    text = report
                    textSize = 12f
                    typeface = Typeface.MONOSPACE
                    setTextIsSelectable(true)
                    setPadding(24, 16, 24, 16)
                }
                val scrollView = ScrollView(this@MainActivity).apply {
                    addView(textView)
                }
                val canAutoRepair = diagnosticValue(report, "can_auto_repair") == "true"
                val repairAction = diagnosticValue(report, "action")
                val builder = AlertDialog.Builder(this@MainActivity)
                    .setTitle("Диагностика: ${service.name}")
                    .setView(scrollView)
                    .setNeutralButton("Копировать", null)
                    .setPositiveButton("OK", null)

                if (canAutoRepair && repairAction.isNotBlank() && repairAction != "none") {
                    builder.setNegativeButton("Починить", null)
                }

                builder
                    .show()
                    .also { dialog ->
                        dialog.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener {
                            copyToClipboard("service_diagnostics_${service.id}", report)
                            toast("Диагностика скопирована")
                        }
                        dialog.getButton(AlertDialog.BUTTON_NEGATIVE)?.setOnClickListener {
                            dialog.dismiss()
                            onServiceRepair(service)
                        }
                    }
            } else {
                showOutput("Не удалось выполнить диагностику", result)
            }
        }
    }

    private fun onServiceRepair(service: ServiceItem) {
        guardedAction("Починка сервиса", service.name) {
            val result = withContext(Dispatchers.IO) { repo.repairService(service.id) }
            if (result.code == 0) {
                setUiBusy(true, "Починка сервиса", "Обновление статуса")
                refreshData()
                toast("Сервис починен")
                setUiBusy(false, "Готово", "Починка завершена")
            } else {
                showOutput("Не удалось починить сервис", result)
            }
        }
    }

    private fun diagnosticValue(report: String, key: String): String {
        val prefix = "$key="
        return report.lineSequence()
            .firstOrNull { it.startsWith(prefix) }
            ?.removePrefix(prefix)
            ?.trim()
            .orEmpty()
    }

    private fun buildValidationMessage(validation: DomainValidation): String = buildString {
        append("Всего доменов: ${validation.totalDomains}, уникальных: ${validation.uniqueDomains}")
        if (validation.invalidDomains.isNotEmpty()) {
            append("\n\nНевалидные домены:\n")
            append(validation.invalidDomains.take(8).joinToString("\n"))
            if (validation.invalidDomains.size > 8) append("\n…ещё ${validation.invalidDomains.size - 8}")
        }
        if (validation.duplicateDomains.isNotEmpty()) {
            append("\n\nДубликаты:\n")
            append(validation.duplicateDomains.take(8).joinToString("\n"))
            if (validation.duplicateDomains.size > 8) append("\n…ещё ${validation.duplicateDomains.size - 8}")
        }
        if (validation.conflicts.isNotEmpty()) {
            append("\n\nКонфликты с другими сервисами:\n")
            append(
                validation.conflicts.take(8).joinToString("\n") { raw ->
                    val parts = raw.split("|")
                    val domain = parts.getOrElse(0) { "" }
                    val otherName = parts.getOrElse(2) { parts.getOrElse(1) { "" } }
                    val otherMode = parts.getOrElse(3) { "" }
                    val relation = parts.getOrElse(4) { "" }
                    val suffix = if (relation == "mode_conflict") " [mode conflict]" else ""
                    "$domain → $otherName ($otherMode)$suffix"
                }
            )
            if (validation.conflicts.size > 8) append("\n…ещё ${validation.conflicts.size - 8}")
        }
        if (!validation.hasIssues) {
            append("\n\nПроблем не найдено.")
        }
    }

    private fun showValidationDialog(title: String, validation: DomainValidation) {
        AlertDialog.Builder(this)
            .setTitle(title)
            .setMessage(buildValidationMessage(validation))
            .setPositiveButton("OK", null)
            .show()
    }

    private fun saveServiceChanges(
        serviceId: String,
        originalMode: String,
        originalTcp: String,
        originalUdp: String,
        originalStun: String,
        originalDomainsText: String,
        mode: String,
        tcp: String,
        udp: String,
        stun: String,
        domainsText: String
    ) {
        guardedAction("Сохранение сервиса", serviceId) {
            if (mode == "vpn" && !hasDomainEntries(domainsText)) {
                toast("Для VPN-сервиса нужны домены")
                setUiBusy(false)
                return@guardedAction
            }
            if (mode == "vpn" && !hasActiveVpnProfile()) {
                val proceed = suspendCancellableCoroutine<Boolean> { cont ->
                    AlertDialog.Builder(this@MainActivity)
                        .setTitle("Нет активного VPN-профиля")
                        .setMessage("Сервис сохранится, но VPN-режим не заработает, пока ты не выберешь профиль.")
                        .setNegativeButton("Отмена") { _, _ -> if (cont.isActive) cont.resume(false) {} }
                        .setPositiveButton("Сохранить") { _, _ -> if (cont.isActive) cont.resume(true) {} }
                        .setOnCancelListener { if (cont.isActive) cont.resume(false) {} }
                        .show()
                }
                if (!proceed) {
                    setUiBusy(false)
                    return@guardedAction
                }
            }
            val validation = withContext(Dispatchers.IO) { repo.validateServiceDomains(serviceId, domainsText) }
            if (validation.hasIssues) {
                val proceed = suspendCancellableCoroutine<Boolean> { cont ->
                    AlertDialog.Builder(this@MainActivity)
                        .setTitle("Сохранить несмотря на предупреждения?")
                        .setMessage(buildValidationMessage(validation))
                        .setNegativeButton("Отмена") { _, _ -> if (cont.isActive) cont.resume(false) {} }
                        .setPositiveButton("Сохранить") { _, _ -> if (cont.isActive) cont.resume(true) {} }
                        .setOnCancelListener { if (cont.isActive) cont.resume(false) {} }
                        .show()
                }
                if (!proceed) return@guardedAction
            }
            val domainsChanged = domainsText.trim() != originalDomainsText.trim()
            val modeChanged = mode != originalMode
            val strategiesChanged = tcp != originalTcp || udp != originalUdp || stun != originalStun

            if (domainsChanged) {
                val domainsResult = withContext(Dispatchers.IO) { repo.saveServiceDomains(serviceId, domainsText) }
                if (domainsResult.code != 0) {
                    showOutput("Не удалось сохранить домены", domainsResult)
                    return@guardedAction
                }
            }
            if (modeChanged) {
                val modeResult = withContext(Dispatchers.IO) { repo.setServiceMode(serviceId, mode) }
                if (modeResult.code != 0) {
                    showOutput("Не удалось изменить режим", modeResult)
                    return@guardedAction
                }
            }
            if (mode == "zapret") {
                if (strategiesChanged || modeChanged) {
                    val tcpResult = withContext(Dispatchers.IO) { repo.setServiceStrategy(serviceId, "tcp", tcp) }
                    val udpResult = withContext(Dispatchers.IO) { repo.setServiceStrategy(serviceId, "udp", udp) }
                    val stunResult = withContext(Dispatchers.IO) { repo.setServiceStrategy(serviceId, "stun", stun) }
                    if (tcpResult.code != 0 || udpResult.code != 0 || stunResult.code != 0) {
                        showOutput(
                            "Не удалось изменить стратегии",
                            ShellResult(
                                code = listOf(tcpResult.code, udpResult.code, stunResult.code).firstOrNull { it != 0 } ?: 1,
                                stdout = listOf(tcpResult.stdout, udpResult.stdout, stunResult.stdout).filter { it.isNotBlank() }.joinToString("\n"),
                                stderr = listOf(tcpResult.stderr, udpResult.stderr, stunResult.stderr).filter { it.isNotBlank() }.joinToString("\n")
                            )
                        )
                        return@guardedAction
                    }
                }
            }
            if (mode == "vpn" && (domainsChanged || modeChanged)) {
                val rebuildResult = withContext(Dispatchers.IO) { repo.rebuildServiceIpsets(serviceId, force = true) }
                if (rebuildResult.code != 0) {
                    showOutput("Не удалось пересобрать IP-списки", rebuildResult)
                    return@guardedAction
                }
            }
            val coverage = withContext(Dispatchers.IO) { repo.getServiceCoverage(serviceId) }
            pendingApplyReason = if (domainsChanged || modeChanged || strategiesChanged) "Настройки сервиса $serviceId сохранены" else pendingApplyReason
            val warn = buildList {
                if (coverage.unresolvedCount > 0) add("unresolved=${coverage.unresolvedCount}")
                if (coverage.modeConflictCount > 0) add("mode_conflicts=${coverage.modeConflictCount}")
            }.joinToString(", ")
            toast(if (!domainsChanged && !modeChanged && !strategiesChanged) "Изменений нет" else if (warn.isBlank()) "Сервис сохранён" else "Сервис сохранён ($warn)")
            refreshData()
            if (pendingApplyReason != null) {
                setUiBusy(false, "Нужно применить", "Нажми Применить, чтобы обновить правила")
            } else {
                setUiBusy(false, "Готово", "Настройки без изменений")
            }
        }
    }

    private fun hasActiveVpnProfile(): Boolean =
        ::currentHealth.isInitialized &&
            currentHealth.activeProfileId.isNotBlank() &&
            currentHealth.activeProfileId != "none"

    private fun hasDomainEntries(domainsText: String): Boolean =
        domainsText.lineSequence().any { line ->
            val trimmed = line.trim()
            trimmed.isNotBlank() && !trimmed.startsWith("#")
        }

    private fun proceedWithVpnProfileWarning(mode: String, message: String, proceed: () -> Unit) {
        if (mode == "vpn" && !hasActiveVpnProfile()) {
            AlertDialog.Builder(this)
                .setTitle("Нет активного VPN-профиля")
                .setMessage(message)
                .setNegativeButton("Отмена", null)
                .setPositiveButton("Продолжить") { _, _ -> proceed() }
                .show()
        } else {
            proceed()
        }
    }

    private fun selectStrategy(spinner: Spinner, list: List<StrategyItem>, selectedId: String) {
        val index = list.indexOfFirst { it.id == selectedId }.takeIf { it >= 0 } ?: 0
        spinner.setSelection(index)
    }

    private fun toggleStrategies(dialogBinding: DialogServiceModeBinding, mode: String) {
        dialogBinding.layoutStrategies.visibility = if (mode == "zapret") android.view.View.VISIBLE else android.view.View.GONE
    }

    private fun showOutput(title: String, result: ShellResult) {
        val message = buildString {
            append("code=")
            append(result.code)
            append("\n\nstdout:\n")
            append(result.stdout.ifBlank { "<empty>" })
            append("\n\nstderr:\n")
            append(result.stderr.ifBlank { "<empty>" })
        }
        AlertDialog.Builder(this)
            .setTitle(title)
            .setMessage(message)
            .setPositiveButton("OK", null)
            .show()
    }

    private fun toast(text: String) {
        Toast.makeText(this, text, Toast.LENGTH_SHORT).show()
    }

    private fun copyToClipboard(label: String, text: String) {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText(label, text))
    }

    private fun openUrl(url: String) {
        if (url.isBlank()) {
            toast("Ссылка недоступна")
            return
        }
        try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        } catch (_: Throwable) {
            toast("Не удалось открыть ссылку")
        }
    }

    private fun compareVersions(left: String, right: String): Int {
        val leftParts = left.removePrefix("v").split('.', '-', '_').map { it.toIntOrNull() ?: 0 }
        val rightParts = right.removePrefix("v").split('.', '-', '_').map { it.toIntOrNull() ?: 0 }
        val max = maxOf(leftParts.size, rightParts.size)
        for (i in 0 until max) {
            val l = leftParts.getOrElse(i) { 0 }
            val r = rightParts.getOrElse(i) { 0 }
            if (l != r) return l.compareTo(r)
        }
        return 0
    }

    private fun readClipboardText(): String {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = clipboard.primaryClip ?: return ""
        if (clip.itemCount == 0) return ""
        return clip.getItemAt(0).coerceToText(this)?.toString().orEmpty()
    }

    private fun readTextFromUri(context: Context, uri: Uri): String {
        return context.contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }.orEmpty()
    }

    companion object {
        private const val KEY_VPN_SECTION_EXPANDED = "vpn_section_expanded"
        private const val KEY_PENDING_APPLY_REASON = "pending_apply_reason"
    }
}
