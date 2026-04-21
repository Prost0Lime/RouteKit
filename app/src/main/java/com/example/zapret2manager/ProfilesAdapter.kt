package com.example.zapret2manager

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import com.example.zapret2manager.databinding.ItemProfileBinding

class ProfilesAdapter(
    private val onActivate: (ProxyProfile) -> Unit,
    private val onDelete: (ProxyProfile) -> Unit
) : RecyclerView.Adapter<ProfilesAdapter.Holder>() {

    private val items = mutableListOf<ProxyProfile>()

    fun submitList(newItems: List<ProxyProfile>) {
        items.clear()
        items.addAll(newItems)
        notifyDataSetChanged()
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): Holder {
        val binding = ItemProfileBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return Holder(binding)
    }

    override fun onBindViewHolder(holder: Holder, position: Int) = holder.bind(items[position])

    override fun getItemCount(): Int = items.size

    inner class Holder(private val binding: ItemProfileBinding) : RecyclerView.ViewHolder(binding.root) {
        fun bind(item: ProxyProfile) {
            binding.tvProfileName.text = item.name
            binding.tvProfileMeta.text = item.serverMeta
            binding.tvProfileId.text = item.id
            binding.tvProfileActive.visibility = if (item.isActive) android.view.View.VISIBLE else android.view.View.GONE
            binding.btnActivate.isEnabled = !item.isActive
            binding.btnActivate.text = if (item.isActive) "Активен" else "Сделать активным"
            binding.btnActivate.setOnClickListener { onActivate(item) }
            binding.btnDelete.setOnClickListener { onDelete(item) }
        }
    }
}
