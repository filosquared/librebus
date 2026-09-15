package com.filiplopes.librebus

import android.util.Log
import com.google.gson.JsonArray
import com.google.gson.JsonElement
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.MediaType.Companion.toMediaType
import org.jsoup.Jsoup
import java.net.URI
import java.net.URLEncoder
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.util.Locale
import java.util.concurrent.TimeUnit

enum class LibrusErrorKind {
    ACCOUNT_TYPE,
    INVALID_CREDENTIALS,
    LOGIN_FLOW,
    ADDITIONAL_VERIFICATION,
    SESSION_EXPIRED,
    UNAVAILABLE,
    UNEXPECTED_RESPONSE,
    MALFORMED_DATA,
    LOCAL_STORAGE,
    GENERIC
}

class LibrusClientError(val kind: LibrusErrorKind, message: String) : Exception(message) {
    constructor(message: String) : this(LibrusErrorKind.GENERIC, message)
}

class LibrusClient {
    private val apiBase = "https://synergia.librus.pl/gateway/api/2.0/"
    private val portalBase = "https://synergia.librus.pl"
    private val oauthHost = "api.librus.pl"
    private val cookies = InMemoryCookieJar()
    private val http = OkHttpClient.Builder()
        .cookieJar(cookies)
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .writeTimeout(20, TimeUnit.SECONDS)
        .followRedirects(true)
        .followSslRedirects(true)
        .build()

    fun login(username: String, password: String): StudentProfile {
        val loginName = username.trim()
        if (loginName.contains("@")) {
            throw LibrusClientError(LibrusErrorKind.ACCOUNT_TYPE, "Use the school-issued Synergia login, not an email address.")
        }
        if (loginName.isEmpty() || password.isEmpty()) {
            throw LibrusClientError(LibrusErrorKind.INVALID_CREDENTIALS, "Enter your Synergia login and password.")
        }

        val portal = request(
            "$portalBase/loguj/portalRodzina",
            headers = mapOf(
                "Referer" to "https://portal.librus.pl/",
                "Accept" to "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
            )
        )
        if (portal.code != 200) throw responseError(portal, "starting the Librus login flow")
        val authUrl = authorizationUrl(portal.finalUrl)

        val loginResponse = request(
            authUrl,
            method = "POST",
            body = formBody(mapOf("action" to "login", "login" to loginName, "pass" to password)),
            headers = mapOf(
                "Accept" to "application/json",
                "Content-Type" to "application/x-www-form-urlencoded"
            )
        )
        if (loginResponse.code == 401 || loginResponse.code == 403) {
            throw LibrusClientError(LibrusErrorKind.INVALID_CREDENTIALS, "Librus rejected this sign-in. Check the school-issued Synergia login and password.")
        }
        if (loginResponse.code != 200) throw responseError(loginResponse, "signing in")
        val loginJson = parseObject(loginResponse.bytes, "the sign-in response")
        val loginStatus = loginJson.string("status").lowercase(Locale.ROOT)
        if (loginStatus == "error") {
            throw LibrusClientError(LibrusErrorKind.INVALID_CREDENTIALS, "Librus rejected this sign-in. Check the school-issued Synergia login and password.")
        }
        if (loginStatus != "ok") {
            throw LibrusClientError(LibrusErrorKind.LOGIN_FLOW, "Librebus could not complete the Librus login flow. Try again in a moment.")
        }
        val nextUrl = authorizationUrl(loginJson.string("goTo"))
        val continuation = request(nextUrl)
        if (continuation.code !in 200..399) throw responseError(continuation, "completing sign-in")
        if (URI(continuation.finalUrl).host != URI(portalBase).host) {
            throw LibrusClientError(LibrusErrorKind.ADDITIONAL_VERIFICATION, "Librus requires an additional verification step on the official Synergia website.")
        }

        val tokenInfo = apiJson("Auth/TokenInfo")
        val identifier = tokenInfo.string("UserIdentifier")
        if (identifier.isEmpty()) throw LibrusClientError(LibrusErrorKind.MALFORMED_DATA, "Librus returned an incomplete login session. Try signing in again.")
        val access = request("$apiBase/Auth/UserInfo/$identifier")
        if (access.code != 200) throw responseError(access, "authorizing access to your school data")
        return fetchProfile()
    }

    fun fetchProfile(): StudentProfile {
        val me = apiJson("Me")
        val userProfile = apiJson("UserProfile")
        val users = apiJson("Users")
        val classes = apiJson("Classes")

        val account = me.obj("Me").obj("Account")
        val schoolClass = classes.obj("Class")
        val tutorId = schoolClass.obj("ClassTutor").string("Id")
        val tutor = userMap(users)[tutorId] ?: JsonObject()
        val number = schoolClass.string("Number")
        val symbol = schoolClass.string("Symbol").uppercase(Locale.getDefault())
        val className = listOf(number, symbol).filter(String::isNotEmpty).joinToString(" ")
        return StudentProfile(
            firstName = account.string("FirstName", "Student"),
            lastName = account.string("LastName"),
            tutorFirstName = tutor.string("FirstName"),
            tutorLastName = tutor.string("LastName"),
            schoolYearStarts = schoolClass.string("BeginSchoolYear"),
            schoolYearMiddles = schoolClass.string("EndFirstSemester"),
            schoolYearEnds = schoolClass.string("EndSchoolYear"),
            type = userProfile.obj("UserProfile").string("UnitType", "Student").replaceFirstChar { it.uppercase() },
            className = className.ifEmpty { "Class" }
        )
    }

    fun fetchGrades(): List<GradeRecord> {
        val response = apiJson("Grades")
        val categories = gradeCategories(apiJson("Grades/Categories"))
        val comments = commentMap(apiJson("Grades/Comments"))
        val subjects = subjectMap(apiJson("Subjects"))
        val teachers = userMap(apiJson("Users"))
        return response.array("Grades").mapIndexed { index, raw ->
            val subjectId = raw.obj("Subject").string("Id")
            val categoryId = raw.obj("Category").string("Id")
            val addedById = raw.obj("AddedBy").string("Id")
            val category = categories[categoryId] ?: ("Grade" to "none")
            val commentId = raw.array("Comments").firstOrNull()?.asJsonObject?.string("Id") ?: ""
            val addedDate = raw.string("AddDate")
            GradeRecord(
                id = raw.string("Id").ifEmpty { "$subjectId-$addedDate-${raw.string("Grade")}-$index" },
                subject = subjects[subjectId] ?: "Subject",
                value = raw.string("Grade", "—"),
                weight = category.second,
                comment = comments[commentId] ?: "",
                category = category.first,
                isFinal = raw.bool("IsFinal") || raw.bool("IsFinalProposition"),
                isSemester = raw.bool("IsSemester") || raw.bool("IsSemesterProposition"),
                semester = raw.string("Semester"),
                addedDate = addedDate,
                teacher = teacherName(teachers[addedById] ?: JsonObject())
            )
        }.sortedBy { it.subject.lowercase(Locale.getDefault()) }
    }

    fun fetchTimetable(): TimetableData {
        val today = LocalDate.now()
        val pivot = today.plusDays(2)
        val weekStart = pivot.minusDays((pivot.dayOfWeek.value - 1).toLong())
        val weekEnd = weekStart.plusDays(6)
        val dateFrom = weekStart.format(DATE_FORMAT)
        val dateTo = weekEnd.format(DATE_FORMAT)
        val timetable = apiJson("Timetables?weekStart=$dateFrom").obj("Timetable")
        val activities = apiJson("Timetables/OtherActivitiesRegister?dateFrom=$dateFrom&dateTo=$dateTo&hideOutdatedEntries=false")
        val classrooms = classroomMap(apiJson("TimetableEntries"))
        val lessonsByDay = mutableMapOf<String, MutableList<TimetableLesson>>()
        val lessonByStart = mutableMapOf<String, String>()

        timetable.entrySet().forEach { (dateKey, rawDay) ->
            val date = parseDate(dateKey) ?: return@forEach
            val dayName = date.dayOfWeek.getDisplayName(java.time.format.TextStyle.FULL, Locale.ENGLISH)
            if (!rawDay.isJsonArray) return@forEach
            rawDay.asJsonArray.forEachIndexed { index, rawEntry ->
                val lesson = rawEntry.asJsonArray.firstOrNull()?.asJsonObject ?: return@forEachIndexed
                val hourFrom = lesson.string("HourFrom")
                val lessonNumber = lesson.string("LessonNo", "-")
                lessonByStart[hourFrom] = lessonNumber
                val classroomId = lesson.obj("Classroom").string("Id")
                lessonsByDay.getOrPut(dayName) { mutableListOf() }.add(
                    TimetableLesson(
                        id = "$dateKey-$lessonNumber-$index",
                        lessonNumber = lessonNumber,
                        subject = lesson.obj("Subject").string("Name", "Lesson"),
                        isSubstitution = lesson.bool("IsSubstitutionClass"),
                        isCancelled = lesson.bool("IsCanceled"),
                        teacher = teacherName(lesson.obj("Teacher")),
                        hourFrom = hourFrom,
                        hourTo = lesson.string("HourTo"),
                        classroom = classrooms[classroomId] ?: "—"
                    )
                )
            }
        }

        activities.array("data").forEachIndexed { index, item ->
            val date = parseDate(item.string("date")) ?: return@forEachIndexed
            val dayName = date.dayOfWeek.getDisplayName(java.time.format.TextStyle.FULL, Locale.ENGLISH)
            val teacherParts = item.string("teacherName").trim().split(Regex("\\s+")).filter(String::isNotEmpty)
            val teacher = if (teacherParts.size > 1) teacherParts.drop(1).joinToString(" ") + " " + teacherParts.first() else teacherParts.firstOrNull() ?: "—"
            lessonsByDay.getOrPut(dayName) { mutableListOf() }.add(
                TimetableLesson(
                    id = "activity-${item.string("date")}-$index",
                    lessonNumber = lessonByStart[item.string("startTime")] ?: "-",
                    subject = item.string("title", "Activity"),
                    isSubstitution = false,
                    isCancelled = false,
                    teacher = teacher,
                    hourFrom = item.string("startTime"),
                    hourTo = item.string("endTime"),
                    classroom = item.obj("classroom").string("symbol", "—")
                )
            )
        }
        return TimetableData(
            nextWeek = today.get(java.time.temporal.IsoFields.WEEK_OF_WEEK_BASED_YEAR) < weekStart.get(java.time.temporal.IsoFields.WEEK_OF_WEEK_BASED_YEAR),
            days = lessonsByDay.mapValues { (_, value) -> value.sortedBy { it.hourFrom } },
            weekStart = dateFrom
        )
    }

    fun fetchAttendances(): List<AttendanceRecord> {
        val attendances = apiJson("Attendances")
        val teachers = userMap(apiJson("Users"))
        val lessons = lessonSubjectMap(apiJson("Lessons"))
        val subjects = subjectMap(apiJson("Subjects"))
        val types = attendanceTypeMap(apiJson("Attendances/Types"))
        return attendances.array("Attendances").mapIndexed { index, raw ->
            val type = types[raw.obj("Type").string("Id")] ?: AttendanceType("Attendance", "?", false)
            AttendanceRecord(
                id = raw.string("Id").ifEmpty { "attendance-$index" },
                subject = subjects[lessons[raw.obj("Lesson").string("Id")] ?: ""] ?: "Lesson",
                type = type.name,
                shortType = type.short,
                isPresence = type.isPresence,
                addedDate = raw.string("AddDate"),
                date = raw.string("Date"),
                teacher = teacherName(teachers[raw.obj("AddedBy").string("Id")] ?: JsonObject())
            )
        }.reversed()
    }

    fun fetchHomeworks(): List<HomeworkRecord> {
        val homeworks = apiJson("HomeWorks")
        val teachers = userMap(apiJson("Users"))
        val categories = homeworkCategoryMap(apiJson("HomeWorks/Categories"))
        val subjects = subjectMap(apiJson("Subjects"))
        return homeworks.array("HomeWorks").mapIndexed { index, raw ->
            val category = categories[raw.obj("Category").string("Id")] ?: "Homework"
            HomeworkRecord(
                id = raw.string("Id").ifEmpty { "homework-$index" },
                subject = subjects[raw.obj("Subject").string("Id")] ?: "Lesson ${raw.string("LessonNo")}",
                addedBy = teacherName(teachers[raw.obj("CreatedBy").string("Id")] ?: JsonObject()),
                type = category,
                startTime = raw.string("TimeFrom"),
                endTime = raw.string("TimeTo"),
                date = raw.string("Date"),
                addedDate = raw.string("AddDate"),
                content = raw.string("Content")
            )
        }.reversed()
    }

    fun fetchMessages(): List<MessageSummary> {
        val html = portalHtml("/wiadomosci")
        val rows = Jsoup.parse(html).select("tr")
        val messages = rows.mapNotNull { row ->
            val columns = row.select("td")
            if (columns.size <= 1) return@mapNotNull null
            val linkColumn = columns.firstOrNull { column ->
                column.select("a[href]").any { messageId(it.attr("href")).isNotEmpty() }
            } ?: return@mapNotNull null
            val columnIndex = columns.indexOf(linkColumn)
            val href = linkColumn.selectFirst("a[href]")?.attr("href") ?: return@mapNotNull null
            val id = messageId(href)
            if (id.isEmpty()) return@mapNotNull null
            val sender = linkColumn.text().substringBefore("(").trim()
            val subject = columns.getOrNull(columnIndex + 1)?.text()?.trim().orEmpty()
            val date = columns.getOrNull(columnIndex + 2)?.text()?.trim().orEmpty()
            if (subject.isEmpty() && date.isEmpty()) return@mapNotNull null
            val header = "$sender $subject $date".lowercase(Locale.getDefault())
            if (listOf("temat", "subject", "wyslano", "sent").any(header::contains)) return@mapNotNull null
            MessageSummary(id, sender, subject, date)
        }
        val candidateRows = rows.count { it.select("td").size > 1 }
        Log.d(LOG_TAG, "Messages page parsed: rows=" + rows.size + ", candidateRows=" + candidateRows + ", messages=" + messages.size)
        return messages
    }

    fun fetchMessage(id: String): MessageDetail {
        val html = portalHtml("/wiadomosci/${id.replace('-', '/')}")
        val doc = Jsoup.parse(html)
        val content = doc.selectFirst(".container-message-content")?.text()?.trim().orEmpty()
        val subject = doc.selectFirst("table.stretch td")?.text()?.trim().orEmpty()
        return MessageDetail(subject.ifEmpty { "Message" }, content = content)
    }

    private fun apiJson(path: String): JsonObject {
        val response = request(apiBase + path, headers = mapOf("Accept" to "application/json"))
        if (isLoginRedirect(response)) throw LibrusClientError(LibrusErrorKind.SESSION_EXPIRED, "Your Librus session expired. Librebus will try to sign in again.")
        if (response.code != 200) throw responseError(response, "loading $path")
        return parseObject(response.bytes, path)
    }

    private fun portalHtml(path: String): String {
        val response = request(
            portalBase + path,
            headers = mapOf("Accept" to "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
        )
        if (isLoginRedirect(response)) throw LibrusClientError(LibrusErrorKind.SESSION_EXPIRED, "Your Librus session expired. Librebus will try to sign in again.")
        if (response.code != 200) throw responseError(response, "loading $path")
        return response.bytes.toString(Charsets.UTF_8)
    }

    private fun request(url: String, method: String = "GET", body: String? = null, headers: Map<String, String> = emptyMap()): HttpResult {
        val attempts = when (method) {
            "GET" -> 3
            "POST" -> 2
            else -> 1
        }
        repeat(attempts) { attempt ->
            try {
                val builder = Request.Builder().url(url).header("User-Agent", "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36")
                headers.forEach { (key, value) -> builder.header(key, value) }
                if (method == "POST") builder.post((body ?: "").toRequestBody("application/x-www-form-urlencoded".toMediaType()))
                val response = http.newCall(builder.build()).execute()
                response.use {
                    val result = HttpResult(it.code, it.request.url.toString(), it.header("Content-Type").orEmpty(), it.body?.bytes() ?: ByteArray(0))
                    Log.d(LOG_TAG, "${method} ${endpoint(url)} -> ${result.code} ${endpoint(result.finalUrl)} ${result.contentType.substringBefore(';')}")
                    if (result.code < 500 || attempt + 1 >= attempts) return result
                    Log.w(LOG_TAG, "Retrying server error for " + method + " " + endpoint(url))
                }
            } catch (_: Exception) {
                Log.w(LOG_TAG, "Request failed: ${method} ${endpoint(url)} (attempt ${attempt + 1}/${attempts})")
                if (attempt + 1 < attempts) runCatching { Thread.sleep(250L * (attempt + 1)) }
            }
        }
        throw LibrusClientError(LibrusErrorKind.UNAVAILABLE, "Librus is currently unavailable. Check your internet connection and try again.")
    }

    private fun authorizationUrl(value: String): String {
        val url = try {
            URI("https://api.librus.pl/").resolve(value)
        } catch (_: Exception) {
            throw LibrusClientError(LibrusErrorKind.LOGIN_FLOW, "Librebus could not complete the Librus login flow. Try again in a moment.")
        }
        val validPath = url.path == "/OAuth/Authorization" || url.path.startsWith("/OAuth/Authorization/")
        if (url.scheme != "https" || url.host != oauthHost || !validPath || url.userInfo != null || url.port !in listOf(-1, 443) || url.query?.contains("error", ignoreCase = true) == true) {
            throw LibrusClientError(LibrusErrorKind.LOGIN_FLOW, "Librebus could not complete the Librus login flow. Try again in a moment.")
        }
        return url.toString()
    }

    private fun formBody(values: Map<String, String>): String = values.toSortedMap().entries.joinToString("&") {
        "${encode(it.key)}=${encode(it.value)}"
    }

    private fun encode(value: String): String = URLEncoder.encode(value, "UTF-8").replace("+", "%20")

    private fun parseObject(bytes: ByteArray, operation: String): JsonObject {
        val text = bytes.toString(Charsets.UTF_8).trim().removePrefix("\uFEFF").trim()
        if (text.isEmpty()) throw LibrusClientError(LibrusErrorKind.MALFORMED_DATA, "Librus returned an empty response while loading $operation. Try again.")
        return try {
            val parsed = JsonParser.parseString(text)
            if (!parsed.isJsonObject) throw IllegalStateException("Expected a JSON object")
            parsed.asJsonObject
        } catch (_: Exception) {
            throw LibrusClientError(LibrusErrorKind.MALFORMED_DATA, "Librus returned an unreadable response while loading $operation. Try again.")
        }
    }

    private fun isLoginRedirect(response: HttpResult): Boolean {
        val path = runCatching { URI(response.finalUrl).path.lowercase(Locale.ROOT) }.getOrDefault("")
        val body = response.bytesAsText().lowercase(Locale.ROOT)
        val isLoginForm = response.contentType.contains("text/html", ignoreCase = true) &&
            body.contains("type=\"password\"") &&
            (body.contains("name=\"login\"") || body.contains("name='login'"))
        return path.contains("/loguj") ||
            path.contains("/oauth/authorization") ||
            isLoginForm
    }

    private fun responseError(response: HttpResult, operation: String): LibrusClientError = when {
        response.code == 401 || response.code == 403 -> LibrusClientError(LibrusErrorKind.SESSION_EXPIRED, "Your Librus session expired. Librebus will try to sign in again.")
        response.code == 429 -> LibrusClientError(LibrusErrorKind.UNAVAILABLE, "Librus is temporarily limiting requests. Wait a moment and try again.")
        response.code >= 500 -> LibrusClientError(LibrusErrorKind.UNAVAILABLE, "Librus is temporarily unavailable while $operation. Try again in a moment.")
        else -> LibrusClientError(LibrusErrorKind.UNEXPECTED_RESPONSE, "Librus returned an unexpected response while $operation. Try again.")
    }

    private fun endpoint(value: String): String = runCatching {
        val url = URI(value)
        val path = url.path
        val safePath = when {
            path.contains("/Auth/UserInfo/", ignoreCase = true) ->
                path.substringBefore("/Auth/UserInfo/") + "/Auth/UserInfo/<redacted>"
            path.contains("/wiadomosci/", ignoreCase = true) ->
                path.substringBefore("/wiadomosci/") + "/wiadomosci/<redacted>"
            else -> path
        }
        "${url.host}${safePath}"
    }.getOrDefault("unknown")

    private fun userMap(objectValue: JsonObject): Map<String, JsonObject> = objectValue.array("Users").associateBy { it.string("Id") }
    private fun subjectMap(objectValue: JsonObject): Map<String, String> = objectValue.array("Subjects").associate { it.string("Id") to it.string("Name", "Subject") }
    private fun gradeCategories(objectValue: JsonObject): Map<String, Pair<String, String>> = objectValue.array("Categories").associate { it.string("Id") to (it.string("Name", "Grade") to it.string("Weight", "none")) }
    private fun homeworkCategoryMap(objectValue: JsonObject): Map<String, String> = objectValue.array("Categories").associate { it.string("Id") to it.string("Name", "Homework") }
    private fun commentMap(objectValue: JsonObject): Map<String, String> = objectValue.array("Comments").associate { it.string("Id") to it.string("Text") }
    private fun lessonSubjectMap(objectValue: JsonObject): Map<String, String> = objectValue.array("Lessons").associate { it.string("Id") to it.obj("Subject").string("Id") }

    private data class AttendanceType(val name: String, val short: String, val isPresence: Boolean)
    private fun attendanceTypeMap(objectValue: JsonObject): Map<String, AttendanceType> = objectValue.array("Types").associate { it.string("Id") to AttendanceType(it.string("Name", "Attendance"), it.string("Short", "?"), it.bool("IsPresenceKind")) }
    private fun classroomMap(objectValue: JsonObject): Map<String, String> = objectValue.array("TimetableEntries").mapNotNull { entry ->
        val classroom = entry.obj("Classroom")
        classroom.string("Id").takeIf(String::isNotEmpty)?.let { it to classroom.string("Symbol", classroom.string("Name", "—")) }
    }.toMap()
    private fun teacherName(teacher: JsonObject): String = listOf(teacher.string("FirstName"), teacher.string("LastName")).filter(String::isNotEmpty).joinToString(" ")
    private fun parseDate(value: String): LocalDate? = try { LocalDate.parse(value.take(10), DATE_FORMAT) } catch (_: DateTimeParseException) { null }
    private fun messageId(href: String): String = href.substringAfter("wiadomosci/", "").substringBefore('?').trim('/').replace('/', '-')

    private data class HttpResult(val code: Int, val finalUrl: String, val contentType: String, val bytes: ByteArray) {
        fun bytesAsText(): String = bytes.toString(Charsets.UTF_8)
    }
    private class InMemoryCookieJar : CookieJar {
        private val values = mutableListOf<Cookie>()
        override fun loadForRequest(url: HttpUrl): List<Cookie> = synchronized(values) { values.filter { it.matches(url) } }
        override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) = synchronized(values) {
            cookies.forEach { cookie ->
                values.removeAll { it.name == cookie.name && it.domain == cookie.domain && it.path == cookie.path }
                if (!cookie.expiresAt.let { it < System.currentTimeMillis() }) values.add(cookie)
            }
        }
    }

    companion object {
        private const val LOG_TAG = "LibrebusNetwork"
        private val DATE_FORMAT: DateTimeFormatter = DateTimeFormatter.ISO_LOCAL_DATE
    }
}

private fun JsonObject.obj(key: String): JsonObject = get(key)?.takeIf { it.isJsonObject }?.asJsonObject ?: JsonObject()
private fun JsonObject.array(key: String): List<JsonObject> = get(key)?.takeIf { it.isJsonArray }?.asJsonArray?.mapNotNull { it.takeIf(JsonElement::isJsonObject)?.asJsonObject } ?: emptyList()
private fun JsonObject.string(key: String, fallback: String = ""): String = get(key)?.let { value ->
    when {
        value.isJsonNull -> fallback
        value.isJsonPrimitive && value.asJsonPrimitive.isString -> value.asString
        value.isJsonPrimitive -> value.toString().trim('"')
        else -> fallback
    }
} ?: fallback
private fun JsonObject.bool(key: String): Boolean = get(key)?.takeIf { it.isJsonPrimitive }?.asBoolean ?: false
