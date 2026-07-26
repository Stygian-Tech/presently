package tech.stygian.presently.data

import androidx.room.Entity
import androidx.room.PrimaryKey

enum class SaveToPhotosPreference {
    ALWAYS,
    ASK,
    NEVER,
    ;

    fun shouldSave(whenAsked: Boolean): Boolean =
        when (this) {
            ALWAYS -> true
            ASK -> whenAsked
            NEVER -> false
        }
}

@Entity(tableName = "app_settings")
data class AppSettings(
    @PrimaryKey val id: String = PrimaryId,
    val saveToPhotosPreference: String = SaveToPhotosPreference.ASK.name,
) {
    val preference: SaveToPhotosPreference
        get() = runCatching {
            SaveToPhotosPreference.valueOf(saveToPhotosPreference)
        }.getOrDefault(SaveToPhotosPreference.ASK)

    companion object {
        const val PrimaryId = "primary"
    }
}
