package tech.stygian.presently.data

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AppSettingsTest {
    @Test
    fun alwaysSavesRegardlessOfPerPhotoChoice() {
        assertTrue(SaveToPhotosPreference.ALWAYS.shouldSave(whenAsked = false))
        assertTrue(SaveToPhotosPreference.ALWAYS.shouldSave(whenAsked = true))
    }

    @Test
    fun askUsesThePerPhotoChoice() {
        assertFalse(SaveToPhotosPreference.ASK.shouldSave(whenAsked = false))
        assertTrue(SaveToPhotosPreference.ASK.shouldSave(whenAsked = true))
    }

    @Test
    fun neverSkipsSavingRegardlessOfPerPhotoChoice() {
        assertFalse(SaveToPhotosPreference.NEVER.shouldSave(whenAsked = false))
        assertFalse(SaveToPhotosPreference.NEVER.shouldSave(whenAsked = true))
    }

    @Test
    fun invalidStoredPreferenceFallsBackToAsk() {
        val settings = AppSettings(saveToPhotosPreference = "not-a-real-preference")

        assertTrue(settings.preference == SaveToPhotosPreference.ASK)
    }
}
