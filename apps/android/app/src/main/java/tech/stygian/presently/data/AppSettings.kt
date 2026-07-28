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

enum class DefaultCamera {
    REAR,
    FRONT,
}

@Entity(tableName = "app_settings")
data class AppSettings(
    @PrimaryKey val id: String = PrimaryId,
    val saveToPhotosPreference: String = SaveToPhotosPreference.ASK.name,
    val defaultCamera: String = DefaultCamera.REAR.name,
) {
    val preference: SaveToPhotosPreference
        get() = runCatching {
            SaveToPhotosPreference.valueOf(saveToPhotosPreference)
        }.getOrDefault(SaveToPhotosPreference.ASK)

    val cameraPreference: DefaultCamera
        get() = runCatching {
            DefaultCamera.valueOf(defaultCamera)
        }.getOrDefault(DefaultCamera.REAR)

    companion object {
        const val PrimaryId = "primary"
    }
}
