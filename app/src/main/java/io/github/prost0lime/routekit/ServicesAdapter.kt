package io.github.prost0lime.routekit

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import io.github.prost0lime.routekit.databinding.ItemServiceBinding

class ServicesAdapter(
    private val onSetMode: (ServiceItem, String) -> Unit,
    private val onConfigure: (ServiceItem) -> Unit,
    private val onDiagnose: (ServiceItem) -> Unit,
    private val onRepair: (ServiceItem) -> Unit,
    private val onDelete: (ServiceItem) -> Unit
) : RecyclerView.Adapter<ServicesAdapter.Holder>() {

    private val items = mutableListOf<ServiceItem>()
    private val expandedIds = mutableSetOf<String>()
    private var actionsEnabled: Boolean = true

    fun submitList(newItems: List<ServiceItem>) {
        val knownIds = newItems.map { it.id }.toSet()
        expandedIds.retainAll(knownIds)
        items.clear()
        items.addAll(newItems)
        notifyDataSetChanged()
    }

    fun setActionsEnabled(enabled: Boolean) {
        if (actionsEnabled == enabled) return
        actionsEnabled = enabled
        notifyDataSetChanged()
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): Holder {
        val binding = ItemServiceBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return Holder(binding)
    }

    override fun onBindViewHolder(holder: Holder, position: Int) = holder.bind(items[position])

    override fun getItemCount(): Int = items.size

    inner class Holder(private val binding: ItemServiceBinding) : RecyclerView.ViewHolder(binding.root) {
        fun bind(item: ServiceItem) {
            val expanded = expandedIds.contains(item.id)
            binding.tvServiceName.text = item.name
            binding.tvServiceMode.text = item.mode.uppercase()
            binding.tvServiceSummary.text = buildString {
                append("Доменов: ${item.domainCount}")
                if (!item.enabled) append("  •  выключен")
                if (item.mode == "vpn") {
                    when {
                        item.autoIpCount == 0 -> append("  •  IP не собраны")
                        item.coverageStatus == "auto_only" -> append("  •  auto IPv4: ${item.autoIpCount}")
                        item.coverageStatus == "mixed" -> append("  •  auto+ручн. IPv4: ${item.autoIpCount}")
                        else -> append("  •  IPv4: ${item.autoIpCount}")
                    }
                    if (item.autoIpv6Count > 0) append("  •  IPv6: ${item.autoIpv6Count}")
                } else if (item.mode == "zapret") {
                    append("  •  через zapret")
                } else if (item.mode == "direct") {
                    append("  •  напрямую")
                }
                if (item.isCustom) append("  •  custom")
            }
            binding.tvExpandedMeta.text = buildString {
                when (item.mode) {
                    "vpn" -> {
                        append("VPN: ${item.vpnProfile.ifBlank { "active" }}")
                        append("  •  IPv6: ${item.ipv6Status}")
                        append("  •  coverage: ${item.coverageStatus}")
                    }
                    "zapret" -> {
                        append("TCP: ${item.tcpStrategy.ifBlank { "—" }}")
                        append("  •  UDP: ${item.udpStrategy.ifBlank { "—" }}")
                        append("  •  STUN: ${item.stunStrategy.ifBlank { "—" }}")
                    }
                    else -> append("Direct: сервис пойдёт напрямую, без VPN и zapret")
                }
            }
            binding.layoutExpanded.visibility = if (expanded) View.VISIBLE else View.GONE
            binding.ivExpand.rotation = if (expanded) 180f else 0f

            binding.btnDirect.isEnabled = actionsEnabled && item.mode != "direct"
            binding.btnZapret.isEnabled = actionsEnabled && item.mode != "zapret"
            binding.btnVpn.isEnabled = actionsEnabled && item.mode != "vpn"
            binding.btnConfigure.isEnabled = actionsEnabled
            binding.btnDiagnose.isEnabled = actionsEnabled
            binding.btnRepair.isEnabled = actionsEnabled
            binding.btnDelete.isEnabled = actionsEnabled
            binding.btnDelete.visibility = if (item.isCustom) View.VISIBLE else View.GONE

            binding.root.setOnClickListener {
                if (expanded) expandedIds.remove(item.id) else expandedIds.add(item.id)
                notifyItemChanged(bindingAdapterPosition)
            }
            binding.btnDirect.setOnClickListener { if (actionsEnabled) onSetMode(item, "direct") }
            binding.btnZapret.setOnClickListener { if (actionsEnabled) onSetMode(item, "zapret") }
            binding.btnVpn.setOnClickListener { if (actionsEnabled) onSetMode(item, "vpn") }
            binding.btnConfigure.setOnClickListener { if (actionsEnabled) onConfigure(item) }
            binding.btnDiagnose.setOnClickListener { if (actionsEnabled) onDiagnose(item) }
            binding.btnRepair.setOnClickListener { if (actionsEnabled) onRepair(item) }
            binding.btnDelete.setOnClickListener { if (actionsEnabled) onDelete(item) }
        }
    }
}
