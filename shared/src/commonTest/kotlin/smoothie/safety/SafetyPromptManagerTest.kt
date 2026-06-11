package smoothie.safety

import kotlin.test.Test
import kotlin.test.assertEquals
import smoothie.model.CLIType

class SafetyPromptManagerTest {

    @Test
    fun emptyManagerAssemblesEmptyString() {
        val manager = SafetyPromptManager()
        assertEquals("", manager.assembledSystemPrompt(CLIType.CLAUDE_CODE))
    }

    @Test
    fun baseOnlyFallsBackForCliWithoutOwnPrompt() {
        val manager = SafetyPromptManager()
        manager.setBasePrompt("BASE RULES")
        assertEquals("BASE RULES", manager.assembledSystemPrompt(CLIType.CODEX))
    }

    @Test
    fun basePlusPerCliJoinWithBlankLine() {
        val manager = SafetyPromptManager()
        manager.setBasePrompt("BASE")
        manager.setSystemPrompt(CLIType.GEMINI, "GEMINI EXTRAS")
        assertEquals("BASE\n\nGEMINI EXTRAS", manager.assembledSystemPrompt(CLIType.GEMINI))
        assertEquals("BASE", manager.assembledSystemPrompt(CLIType.CLAUDE_CODE))
    }
}
