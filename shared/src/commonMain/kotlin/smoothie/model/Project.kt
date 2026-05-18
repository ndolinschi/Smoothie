package smoothie.model

import kotlinx.serialization.Serializable

@Serializable
data class Project(
    val name: String,
    val path: String,
    val isGit: Boolean,
)

@Serializable
data class BrowseEntry(
    val name: String,
    val path: String,
    val isDirectory: Boolean,
    val isGit: Boolean,
    val isAllowed: Boolean,
)

@Serializable
data class BrowseResponse(
    val current: String?,
    val parent: String?,
    val entries: List<BrowseEntry>,
    val roots: List<String>,
)

@Serializable
data class FileEntry(
    val path: String,
    val fullPath: String,
    val size: Long,
)

@Serializable
data class FileContent(
    val path: String,
    val content: String,
    val size: Long,
    val truncated: Boolean,
)
