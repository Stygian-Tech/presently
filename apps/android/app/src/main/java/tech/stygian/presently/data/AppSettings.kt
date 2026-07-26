package tech.stygian.presently.data

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "app_settings")
data class AppSettings(
    @PrimaryKey val id: String = PrimaryId,
    val saveToPhotos: Boolean = false,
) {
    companion object {
        const val PrimaryId = "primary"
    }
}
