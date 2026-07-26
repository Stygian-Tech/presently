package tech.stygian.presently.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

@Database(
    entities = [LocalStoryDraft::class, AppSettings::class],
    version = 1,
    exportSchema = true,
)
abstract class PresentlyDatabase : RoomDatabase() {
    abstract fun presentlyDao(): PresentlyDao

    companion object {
        @Volatile
        private var instance: PresentlyDatabase? = null

        fun get(context: Context): PresentlyDatabase =
            instance ?: synchronized(this) {
                instance ?: Room.databaseBuilder(
                    context.applicationContext,
                    PresentlyDatabase::class.java,
                    "presently.db",
                ).build().also { instance = it }
            }
    }
}
