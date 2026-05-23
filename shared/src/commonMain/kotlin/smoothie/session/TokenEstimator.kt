package smoothie.session

/**
 * Rough chars-to-tokens estimator. ~4 chars per token is the Anthropic /
 * OpenAI ballpark for English text; non-Latin scripts skew higher and
 * code skews lower, but for a percent-of-budget gauge the inaccuracy
 * dissolves into the gradient. Kept as a single-function module so we
 * can swap to a real tokenizer (cl100k, claude's tokenizer JS port,
 * etc.) without chasing call sites.
 *
 * Returns 0 for empty input rather than 1 — important because the
 * status footer hides the percent ring when total tokens == 0.
 */
object TokenEstimator {
    fun estimate(text: String): Int {
        if (text.isEmpty()) return 0
        // Round up so a single-char message reports as 1 token, not 0.
        return (text.length + 3) / 4
    }
}
