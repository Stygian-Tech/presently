package tech.stygian.presently.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Upsert
import kotlinx.coroutines.flow.Flow

@Dao
interface PresentlyDao {
    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insertDraft(draft: LocalStoryDraft)

    @Upsert
    suspend fun upsertSettings(settings: AppSettings)

    @Query("SELECT * FROM app_settings WHERE id = 'primary' LIMIT 1")
    fun observeSettings(): Flow<AppSettings?>
}
