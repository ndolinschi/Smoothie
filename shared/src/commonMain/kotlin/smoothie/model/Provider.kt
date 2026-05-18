package smoothie.model

import kotlinx.serialization.Serializable

/// Declarative description of what a provider supports. Drives conditional UI
/// rendering (whether the composer shows a reasoning-effort segmented control,
/// which models the picker offers, etc.) without each view querying the adapter
/// directly.
@Serializable
data class ProviderFeatures(
    val supportsModelPicker: Boolean,
    val supportsReasoningEffort: Boolean,
    val supportsModes: Boolean,
    val defaultModel: String?,
    val availableModels: List<String>,
    val availableReasoningEfforts: List<String>,
    val availableModes: List<String>,
    val slashCommands: List<SlashCommand>,
)

@Serializable
data class SlashCommand(
    val name: String,
    val description: String,
)

@Serializable
data class AdapterInfo(
    val cli: CLIType,
    val installed: Boolean,
    val version: String?,
    val features: ProviderFeatures?,
)
