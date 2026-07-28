package tech.stygian.presently.story

import java.time.Instant
import org.json.JSONObject

object FlashesActorProfileContract {
    const val Collection = "blue.flashes.actor.profile"
    const val RecordKey = "self"
}

object FlashesActorProfileFactory {
    fun create(createdAt: Instant): JSONObject = JSONObject().apply {
        put("\$type", FlashesActorProfileContract.Collection)
        put("createdAt", createdAt.toString())
        put("showFeeds", true)
        put("showLikes", false)
        put("showLists", true)
        put("showMedia", true)
        put("mediaLayout", "grid")
        put("enablePortfolio", false)
        put("portfolioLayout", "grid")
        put("allowRawDownload", false)
    }
}
