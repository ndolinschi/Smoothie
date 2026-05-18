package smoothie.safety

import smoothie.model.CLIType

/**
 * In v1 the prompts directory was read from disk by the Swift layer. In v2 the
 * Swift layer is still the side closer to the filesystem, so it pushes prompt
 * content into this manager at startup; Kotlin business code asks for the
 * assembled system-prompt text for a given CLI.
 */
class SafetyPromptManager {
    private var basePrompt: String = ""
    private val perCliSystemPrompt = mutableMapOf<CLIType, String>()
    private val perCliResumePrompt = mutableMapOf<CLIType, String>()

    fun setBasePrompt(text: String) { basePrompt = text }
    fun setSystemPrompt(cli: CLIType, text: String) { perCliSystemPrompt[cli] = text }
    fun setResumePrompt(cli: CLIType, text: String) { perCliResumePrompt[cli] = text }

    /** Returns the safety + per-CLI system prompt joined with a blank line.
     *  Empty string if nothing has been loaded yet. */
    fun assembledSystemPrompt(cli: CLIType): String {
        val per = perCliSystemPrompt[cli] ?: ""
        return when {
            basePrompt.isBlank() && per.isBlank() -> ""
            basePrompt.isBlank() -> per
            per.isBlank() -> basePrompt
            else -> "$basePrompt\n\n$per"
        }
    }

    fun resumePromptTemplate(cli: CLIType): String? = perCliResumePrompt[cli]
}
