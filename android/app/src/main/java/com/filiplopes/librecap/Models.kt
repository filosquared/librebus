package com.filiplopes.librecap

import java.time.Instant

data class StudentProfile(
    val firstName: String = "Student",
    val lastName: String = "",
    val tutorFirstName: String = "",
    val tutorLastName: String = "",
    val schoolYearStarts: String = "",
    val schoolYearMiddles: String = "",
    val schoolYearEnds: String = "",
    val type: String = "Student",
    val className: String = "Class"
) {
    val fullName: String get() = listOf(firstName, lastName).filter(String::isNotBlank).joinToString(" ")
    val tutorName: String get() = listOf(tutorFirstName, tutorLastName).filter(String::isNotBlank).joinToString(" ")
}

data class GradeRecord(
    val id: String,
    val subject: String,
    val value: String,
    val weight: String,
    val comment: String,
    val category: String,
    val isFinal: Boolean,
    val isSemester: Boolean,
    val semester: String,
    val addedDate: String,
    val teacher: String
) {
    val numericValue: Double?
        get() {
            val normalized = value.trim().replace(',', '.').replace(Regex("\\s+"), "")
            val grade = Regex("^([1-6])([+-])?$").matchEntire(normalized)
            if (grade != null) {
                val base = grade.groupValues[1].toDouble()
                val adjustment = when (grade.groupValues[2]) {
                    "+" -> 0.5
                    "-" -> -0.5
                    else -> 0.0
                }
                return (base + adjustment).coerceIn(1.0, 6.0)
            }
            return normalized.toDoubleOrNull()
        }
    fun belongsTo(semesterFilter: GradeSemester): Boolean {
        if (semesterFilter == GradeSemester.ALL) return true
        val lower = semester.lowercase()
        return when (semesterFilter) {
            GradeSemester.FIRST -> lower.contains("1") || lower.contains("first") || lower.contains("pierw")
            GradeSemester.SECOND -> lower.contains("2") || lower.contains("second") || lower.contains("drug")
            GradeSemester.ALL -> true
        }
    }
}

data class TimetableLesson(
    val id: String,
    val lessonNumber: String,
    val subject: String,
    val isSubstitution: Boolean,
    val isCancelled: Boolean,
    val teacher: String,
    val hourFrom: String,
    val hourTo: String,
    val classroom: String,
    val originalSubject: String? = null,
    val originalTeacher: String? = null
) {
    fun startMinutes(): Int? = hourFrom.toMinutes()
    fun endMinutes(): Int? = hourTo.toMinutes()

    val displaySubject: String
        get() = originalSubject
            ?.takeIf { isSubstitution && it.isNotBlank() && !it.equals(subject, ignoreCase = true) }
            ?.let { "$subject > $it" }
            ?: subject

    val hasOriginalTeacher: Boolean
        get() = isSubstitution && !originalTeacher.isNullOrBlank() && !originalTeacher.equals(teacher, ignoreCase = true)
}

enum class MessageFolder { INBOX, SENT, ANNOUNCEMENTS, NOTES }

data class MessageRecipient(
    val id: String,
    val name: String,
    val group: String
)

data class TimetableData(
    val nextWeek: Boolean = false,
    val days: Map<String, List<TimetableLesson>> = emptyMap(),
    val weekStart: String? = null
)

data class AttendanceRecord(
    val id: String,
    val subject: String,
    val type: String,
    val shortType: String,
    val isPresence: Boolean,
    val addedDate: String,
    val date: String,
    val teacher: String
)

data class HomeworkRecord(
    val id: String,
    val subject: String,
    val addedBy: String,
    val type: String,
    val startTime: String,
    val endTime: String,
    val date: String,
    val addedDate: String,
    val content: String
) {
    val isAssessment: Boolean
        get() = type.lowercase().let { it.contains("sprawdz") || it.contains("kartk") || it.contains("class") || it.contains("test") }
}

data class MessageSummary(
    val id: String,
    val sender: String,
    val subject: String,
    val date: String,
    val folder: MessageFolder = MessageFolder.INBOX,
    val content: String = ""
) {
    val isLikelyHeaderRow: Boolean
        get() = "$sender $subject $date".lowercase().let {
            it.contains("temat") || it.contains("subject") || it.contains("wyslano") || it.contains("sent") || it.contains("napisz") || it.contains("archiwum") || it.contains("etykiety") || it.contains("kosz")
        }
}

data class MessageDetail(
    val subject: String,
    val sender: String = "",
    val date: String = "",
    val content: String
)

data class SchoolNote(
    val id: String,
    val text: String,
    val reminds: Boolean,
    val isNoLongerRelevant: Boolean,
    val updatedAt: String = Instant.now().toString()
)

data class CachedSchoolData(
    val profile: StudentProfile? = null,
    val grades: List<GradeRecord> = emptyList(),
    val timetable: TimetableData? = null,
    val attendances: List<AttendanceRecord> = emptyList(),
    val homeworks: List<HomeworkRecord> = emptyList(),
    val messages: List<MessageSummary> = emptyList(),
    val luckyNumber: Int? = null,
    val lastSync: String? = null,
    val timetableUpdatedAt: String? = null,
    val gradesUpdatedAt: String? = null,
    val homeworksUpdatedAt: String? = null
)

enum class AppLanguage { ENGLISH, POLISH }
enum class AppAppearance { SYSTEM, LIGHT, DARK }
enum class GradeSemester { FIRST, SECOND, ALL }

fun String.toMinutes(): Int? {
    val parts = trim().split(":")
    if (parts.size != 2) return null
    return parts[0].toIntOrNull()?.times(60)?.plus(parts[1].toIntOrNull() ?: return null)
}

fun String.dayLabel(language: AppLanguage): String = when (this) {
    "Monday" -> if (language == AppLanguage.POLISH) "Poniedziałek" else this
    "Tuesday" -> if (language == AppLanguage.POLISH) "Wtorek" else this
    "Wednesday" -> if (language == AppLanguage.POLISH) "Środa" else this
    "Thursday" -> if (language == AppLanguage.POLISH) "Czwartek" else this
    "Friday" -> if (language == AppLanguage.POLISH) "Piątek" else this
    "Saturday" -> if (language == AppLanguage.POLISH) "Sobota" else this
    "Sunday" -> if (language == AppLanguage.POLISH) "Niedziela" else this
    else -> this
}
