package com.filiplopes.librecap

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant

data class SchoolUiState(
    val ready: Boolean = false,
    val authenticated: Boolean = false,
    val syncing: Boolean = false,
    val username: String = "",
    val data: CachedSchoolData = CachedSchoolData(),
    val notes: List<SchoolNote> = emptyList(),
    val error: String? = null,
    val language: AppLanguage = AppLanguage.ENGLISH,
    val appearance: AppAppearance = AppAppearance.SYSTEM,
    val automaticSync: Boolean = true,
    val availableUpdate: AppRelease? = null,
    val checkingForUpdates: Boolean = false
)

class SchoolViewModel(application: Application) : AndroidViewModel(application) {
    private val context = application.applicationContext
    private val localStore = LocalStore(context)
    private val credentials = CredentialStore(context)
    private val releaseChecker = GitHubReleaseChecker()
    private val currentAppVersion = context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: "0.0.0"
    private val preferences = context.getSharedPreferences("settings", 0)
    private var client: LibrusClient? = null
    private var syncJob: Job? = null
    private var automaticJob: Job? = null
    private var generation = 0

    var state = androidx.compose.runtime.mutableStateOf(loadInitial())
        private set
    var currentMessage = androidx.compose.runtime.mutableStateOf<MessageDetail?>(null)
        private set

    init {
        checkForUpdates()
        val saved = credentials.load()
        if (saved != null) {
            state.value = state.value.copy(username = saved.username, ready = true, authenticated = state.value.data.profile != null, syncing = true)
            val currentGeneration = generation
            viewModelScope.launch { restore(saved, currentGeneration) }
        } else {
            state.value = state.value.copy(ready = true)
        }
        startAutomaticSync()
    }

    fun checkForUpdates() {
        if (state.value.checkingForUpdates) return
        update { it.copy(checkingForUpdates = true) }
        viewModelScope.launch {
            val release = runCatching { releaseChecker.fetchLatest() }.getOrNull()
            val available = release?.takeIf { GitHubReleaseChecker.isNewer(it.tagName, currentAppVersion) }
            update { it.copy(availableUpdate = available, checkingForUpdates = false) }
        }
    }

    fun login(username: String, password: String) {
        val trimmed = username.trim()
        generation += 1
        val currentGeneration = generation
        update { it.copy(syncing = true, error = null) }
        viewModelScope.launch {
            try {
                val result = withContext(Dispatchers.IO) { LibrusClient().also { newClient -> newClient.login(trimmed, password) } }
                if (currentGeneration != generation) return@launch
                client = result
                credentials.save(StoredCredentials(trimmed, password))
                val profile = withContext(Dispatchers.IO) { result.fetchProfile() }
                val fresh = CachedSchoolData(profile = profile)
                update { it.copy(ready = true, authenticated = true, username = trimmed, data = fresh) }
                syncInternal(currentGeneration)
            } catch (error: Exception) {
                if (currentGeneration == generation) update { it.copy(ready = true, syncing = false, error = error.message ?: "Sign-in failed.") }
            }
        }
    }

    fun sync() {
        val currentGeneration = generation
        if (client == null || state.value.syncing) return
        syncJob?.cancel()
        syncJob = viewModelScope.launch { syncInternal(currentGeneration) }
    }

    private suspend fun syncInternal(currentGeneration: Int) {
        val activeClient = client ?: return
        update { it.copy(syncing = true, error = null) }
        var refreshed = state.value.data
        var firstError: String? = null
        suspend fun <T> load(block: suspend () -> T, apply: (T) -> Unit) {
            try { apply(withContext(Dispatchers.IO) { block() }) } catch (error: Exception) { firstError = firstError ?: error.message }
        }
        load({ activeClient.fetchProfile() }) { refreshed = refreshed.copy(profile = it) }
        load({ activeClient.fetchGrades() }) { refreshed = refreshed.copy(grades = it, gradesUpdatedAt = Instant.now().toString()) }
        load({ activeClient.fetchTimetable() }) { refreshed = refreshed.copy(timetable = it, timetableUpdatedAt = Instant.now().toString()) }
        load({ activeClient.fetchAttendances() }) { refreshed = refreshed.copy(attendances = it) }
        load({ activeClient.fetchHomeworks() }) { refreshed = refreshed.copy(homeworks = it, homeworksUpdatedAt = Instant.now().toString()) }
        load({ activeClient.fetchMessages() }) { refreshed = refreshed.copy(messages = it) }
        if (currentGeneration != generation) return
        refreshed = refreshed.copy(lastSync = Instant.now().toString())
        localStore.save(refreshed)
        update { it.copy(data = refreshed, authenticated = true, ready = true, syncing = false, error = firstError) }
    }

    private suspend fun restore(saved: StoredCredentials, currentGeneration: Int) {
        try {
            val restored = withContext(Dispatchers.IO) { LibrusClient().also { it.login(saved.username, saved.password) } }
            if (currentGeneration != generation) return
            client = restored
            update { it.copy(authenticated = true, ready = true, syncing = false) }
            syncInternal(currentGeneration)
        } catch (error: Exception) {
            if (currentGeneration == generation) update { it.copy(ready = true, syncing = false, error = if (it.authenticated) "Showing saved data. Sync failed: ${error.message}" else "Please sign in again: ${error.message}") }
        }
    }

    fun logout() {
        generation += 1
        client = null
        syncJob?.cancel()
        credentials.clear()
        localStore.clear()
        update { it.copy(ready = true, authenticated = false, syncing = false, username = "", data = CachedSchoolData(), notes = emptyList(), error = null) }
    }

    fun saveNote(id: String, text: String, reminds: Boolean, noLongerRelevant: Boolean) {
        val updated = state.value.notes.filterNot { it.id == id }.toMutableList()
        if (text.isNotBlank() || reminds || noLongerRelevant) updated += SchoolNote(id, text, reminds, noLongerRelevant)
        preferences.edit().putString("notes", com.google.gson.Gson().toJson(updated)).apply()
        update { it.copy(notes = updated) }
    }

    fun note(id: String): SchoolNote? = state.value.notes.firstOrNull { it.id == id }
    fun loadMessage(id: String) {
        currentMessage.value = null
        val activeClient = client ?: return
        viewModelScope.launch {
            currentMessage.value = runCatching { withContext(Dispatchers.IO) { activeClient.fetchMessage(id) } }.getOrNull()
        }
    }
    fun setLanguage(language: AppLanguage) { preferences.edit().putString("language", language.name).apply(); update { it.copy(language = language) } }
    fun setAppearance(appearance: AppAppearance) { preferences.edit().putString("appearance", appearance.name).apply(); update { it.copy(appearance = appearance) } }
    fun setAutomaticSync(enabled: Boolean) { preferences.edit().putBoolean("automatic_sync", enabled).apply(); update { it.copy(automaticSync = enabled) }; startAutomaticSync() }

    private fun startAutomaticSync() {
        automaticJob?.cancel()
        automaticJob = viewModelScope.launch {
            while (isActive) {
                delay(45 * 60 * 1000L)
                if (state.value.automaticSync && state.value.authenticated && !state.value.syncing) syncInternal(generation)
            }
        }
    }

    private fun update(block: (SchoolUiState) -> SchoolUiState) { state.value = block(state.value) }

    private fun loadInitial(): SchoolUiState {
        val data = localStore.load()
        val notes = runCatching {
            com.google.gson.Gson().fromJson(preferences.getString("notes", "[]"), Array<SchoolNote>::class.java)?.toList() ?: emptyList()
        }.getOrDefault(emptyList())
        return SchoolUiState(
            data = data,
            notes = notes,
            language = runCatching { AppLanguage.valueOf(preferences.getString("language", AppLanguage.ENGLISH.name)!!) }.getOrDefault(AppLanguage.ENGLISH),
            appearance = runCatching { AppAppearance.valueOf(preferences.getString("appearance", AppAppearance.SYSTEM.name)!!) }.getOrDefault(AppAppearance.SYSTEM),
            automaticSync = preferences.getBoolean("automatic_sync", true)
        )
    }
}
