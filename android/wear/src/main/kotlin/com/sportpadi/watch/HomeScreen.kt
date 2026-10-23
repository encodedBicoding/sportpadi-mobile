package com.sportpadi.watch

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.Card
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.Text
import androidx.wear.compose.navigation.SwipeDismissableNavHost
import androidx.wear.compose.navigation.composable
import androidx.wear.compose.navigation.rememberSwipeDismissableNavController
import kotlinx.coroutines.launch

@Composable
fun WatchNav(activity: MainActivity) {
    val nav = rememberSwipeDismissableNavController()
    val ctx by ContextStore.ctx.collectAsState()
    // The phone opened officiant mode on a match, or a notification asked: follow, once.
    var followed by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(ctx.currentGameId, activity.requestedGameId) {
        val id = activity.requestedGameId ?: ctx.currentGameId
        if (id != null && id != followed) {
            followed = id
            activity.consumeRequested()
            nav.navigate("game/$id") { launchSingleTop = true }
        }
    }
    SwipeDismissableNavHost(navController = nav, startDestination = "home") {
        composable("home") { HomeScreen(onOpen = { nav.navigate("game/$it") }) }
        composable("game/{id}") { entry ->
            GameScreen(gameId = entry.arguments?.getString("id") ?: "", activity = activity, onExit = { nav.popBackStack() })
        }
    }
}

@Composable
fun HomeScreen(onOpen: (String) -> Unit) {
    val ctx by ContextStore.ctx.collectAsState()
    var home by remember { mutableStateOf<Home?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(false) }
    var responding by remember { mutableStateOf<String?>(null) }
    val scope = androidx.compose.runtime.rememberCoroutineScope()

    suspend fun load() {
        loading = true
        try { home = ApiClient.home(); error = null } catch (e: Exception) { error = e.message } finally { loading = false }
    }
    LaunchedEffect(ctx.token) { if (ctx.signedIn) load() }
    LaunchedEffect(Unit) { UsageTracker.screen("/watch") }
    LifecycleResumeEffect(Unit) { scope.launch { if (ctx.signedIn) load() }; onPauseOrDispose {} }

    when {
        ctx.needsPhoneUpdate -> Pitch("Update SportPadi", "Update the app on your phone to use the watch.")
        !ctx.signedIn -> Pitch("Open SportPadi on your phone", "Sign in there once — the watch follows.")
        home == null && loading -> androidx.compose.foundation.layout.Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        home == null && error != null -> Pitch(error ?: "", "Tap to try again") { scope.launch { load() } }
        else -> {
            val h = home ?: return
            ScalingLazyColumn(modifier = Modifier.fillMaxSize()) {
                if (h.invites.isNotEmpty()) {
                    item { Text("Invites", fontSize = 12.sp, color = Color(0xFF6EDC9E), modifier = Modifier.padding(top = 4.dp)) }
                    items(h.invites) { inv ->
                        Card(onClick = {}) {
                            Column {
                                Text(inv.title, fontSize = 14.sp, maxLines = 2)
                                if (inv.teams.isNotEmpty()) Text(inv.teams.joinToString(" v "), fontSize = 12.sp)
                                Text(listOfNotNull(inv.groupName, whenLine(inv.date, inv.startTime).ifEmpty { null }).joinToString(" · "), fontSize = 10.sp, color = Color.Gray)
                                Spacer(Modifier.height(6.dp))
                                Row {
                                    Button(onClick = { scope.launch { responding = inv.gameId; try { ApiClient.respond(inv.gameId, true); load(); onOpen(inv.gameId) } catch (e: Exception) { error = e.message } finally { responding = null } } },
                                        enabled = responding == null, colors = ButtonDefaults.primaryButtonColors(backgroundColor = Color(0xFF1B7A4F))) { Text("✓") }
                                    Spacer(Modifier.width(8.dp))
                                    Button(onClick = { scope.launch { responding = inv.gameId; try { ApiClient.respond(inv.gameId, false); load() } catch (e: Exception) { error = e.message } finally { responding = null } } },
                                        enabled = responding == null, colors = ButtonDefaults.secondaryButtonColors()) { Text("✕") }
                                }
                            }
                        }
                    }
                }
                item { Text(if (h.games.isEmpty()) "" else "My matches", fontSize = 12.sp, color = Color.Gray, modifier = Modifier.padding(top = 6.dp)) }
                if (h.games.isEmpty()) {
                    item { Text("No matches to officiate in the next week.", fontSize = 12.sp, color = Color.Gray, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(8.dp)) }
                } else {
                    items(h.games) { g ->
                        Chip(
                            onClick = { onOpen(g.id) },
                            label = { Text(g.title, maxLines = 2) },
                            secondaryLabel = { Text(if (g.status == "live") "LIVE · ${g.scoreline}" else whenLine(g.event?.date, g.event?.startTime), color = if (g.status == "live") Color(0xFFFF8A84) else Color.Gray) },
                            colors = ChipDefaults.secondaryChipColors(),
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun Pitch(title: String, text: String, onTap: (() -> Unit)? = null) {
    Column(
        Modifier.fillMaxSize().padding(16.dp).let { m -> if (onTap != null) m.then(Modifier) else m },
        verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(title, fontSize = 15.sp, textAlign = TextAlign.Center)
        Spacer(Modifier.height(4.dp))
        Text(text, fontSize = 12.sp, color = Color.Gray, textAlign = TextAlign.Center)
        if (onTap != null) {
            Spacer(Modifier.height(8.dp))
            Chip(onClick = onTap, label = { Text("Retry") }, colors = ChipDefaults.secondaryChipColors())
        }
    }
}
