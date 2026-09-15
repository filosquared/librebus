package com.filiplopes.librebus

import android.content.Context
import com.google.gson.Gson
import java.io.File

class LocalStore(context: Context) {
    private val file = File(context.filesDir, "school_data.json")
    private val gson = Gson()

    fun load(): CachedSchoolData = runCatching {
        if (!file.exists()) CachedSchoolData() else gson.fromJson(file.readText(), CachedSchoolData::class.java) ?: CachedSchoolData()
    }.getOrDefault(CachedSchoolData())

    fun save(data: CachedSchoolData): Boolean = runCatching {
            val temporary = File(file.parentFile, "school_data.json.tmp")
            temporary.writeText(gson.toJson(data))
            if (!temporary.renameTo(file)) {
                file.writeText(gson.toJson(data))
                temporary.delete()
            }
        }.isSuccess

    fun clear() { file.delete() }
}

data class StoredCredentials(val username: String, val password: String)
