package smoothie.adapters

import smoothie.model.AdapterInfo
import smoothie.model.CLIType

/**
 * Registry of available adapters. Currently a static set — Claude is the only
 * adapter implemented in P2; Gemini, Codex, OpenCode are added in P7.
 *
 * Adapter installation status and version are populated by the Swift macOS
 * layer (which can run `which <bin>` and `<bin> --version`) and pushed into
 * the registry via [setAdapterInfo].
 */
class AdapterRegistry {
    private val parsers = mutableMapOf<CLIType, AdapterParser>()
    private val infos = mutableMapOf<CLIType, AdapterInfo>()

    init {
        register(ClaudeAdapter())
        register(GeminiAdapter())
        register(OpenCodeAdapter())
    }

    private fun register(parser: AdapterParser) {
        parsers[parser.cli] = parser
        infos[parser.cli] = parser.info
    }

    fun parserFor(cli: CLIType): AdapterParser? = parsers[cli]

    fun all(): List<AdapterInfo> = CLIType.entries.map { type ->
        infos[type] ?: AdapterInfo(type, installed = false, version = null, features = null)
    }

    /** Called by the macOS host layer after probing the system. */
    fun setAdapterInfo(cli: CLIType, installed: Boolean, version: String?) {
        val existingFeatures = parsers[cli]?.info?.features
        infos[cli] = AdapterInfo(
            cli = cli,
            installed = installed,
            version = version,
            features = existingFeatures,
        )
    }
}
