package com.sportpadi.watch

import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.WearableListenerService

/** Wakes for the phone's context writes, even when the app isn't running. */
class DataLayerService : WearableListenerService() {
    override fun onDataChanged(events: DataEventBuffer) {
        ContextStore.init(applicationContext)
        for (e in events) if (e.type == DataEvent.TYPE_CHANGED) ContextStore.apply(e.dataItem)
    }
}
