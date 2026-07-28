package tech.stygian.presently.data

import android.content.Context
import androidx.room.Database
import androidx.room.migration.Migration
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.sqlite.db.SupportSQLiteDatabase

@Database(
    entities = [LocalStoryDraft::class, AppSettings::class],
    version = 4,
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
                )
                    .addMigrations(Migration1To2, Migration2To3, Migration3To4)
                    .build()
                    .also { instance = it }
            }

        private val Migration1To2 = object : Migration(1, 2) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS app_settings_new (
                        id TEXT NOT NULL,
                        saveToPhotosPreference TEXT NOT NULL,
                        PRIMARY KEY(id)
                    )
                    """.trimIndent(),
                )
                database.execSQL(
                    """
                    INSERT INTO app_settings_new (id, saveToPhotosPreference)
                    SELECT id, CASE WHEN saveToPhotos = 1 THEN 'ALWAYS' ELSE 'ASK' END
                    FROM app_settings
                    """.trimIndent(),
                )
                database.execSQL("DROP TABLE app_settings")
                database.execSQL("ALTER TABLE app_settings_new RENAME TO app_settings")
            }
        }

        private val Migration2To3 = object : Migration(2, 3) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL(
                    "ALTER TABLE local_story_drafts ADD COLUMN publishedCid TEXT",
                )
                database.execSQL(
                    "ALTER TABLE local_story_drafts ADD COLUMN recordKey TEXT",
                )
            }
        }

        private val Migration3To4 = object : Migration(3, 4) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL(
                    "ALTER TABLE app_settings ADD COLUMN defaultCamera " +
                        "TEXT NOT NULL DEFAULT 'REAR'",
                )
            }
        }
    }
}
