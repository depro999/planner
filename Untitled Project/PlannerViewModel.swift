import SwiftUI
import Observation

// MARK: - FORMATO NUMÉRICO (respeta coma/punto según el idioma del dispositivo)
extension Double {
    /// Nota con 2 decimales: 7,25 (es) / 7.25 (en)
    var gradeText: String { formatted(.number.precision(.fractionLength(2))) }
    /// 0 o 1 decimal: 6 → "6", 6.5 → "6,5"
    var compactText: String { formatted(.number.precision(.fractionLength(0...1))) }
    /// 0 a 2 decimales sin ceros sobrantes: 2 → "2", 7.5 → "7,5", 7.35 → "7,35"
    var flexibleText: String { formatted(.number.precision(.fractionLength(0...2))) }
}

extension String {
    /// Acepta coma o punto como separador decimal
    var decimalValue: Double? {
        Double(trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }
}

// MARK: MODELOS UNIFICADOS Y COMPARTIDOS
/// Parte de una evaluación (parcial, práctica…). Su nota cuenta por igual dentro de la evaluación.
struct EvaluationComponent: Identifiable, Codable {
    let id: UUID
    var name: String
    var date: Date
    var grade: Double?
    var calendarEventID: String?

    init(id: UUID = UUID(), name: String, date: Date, grade: Double? = nil, calendarEventID: String? = nil) {
        self.id = id
        self.name = name
        self.date = date
        self.grade = grade
        self.calendarEventID = calendarEventID
    }
}

struct Evaluation: Identifiable, Codable {
    let id: UUID
    var name: String
    var weight: Double
    var date: Date?
    var period: String
    var grade: Double?
    var calendarEventID: String?
    /// Opcional. Si hay componentes, la nota es su media simple y la evaluación no tiene fecha propia.
    var components: [EvaluationComponent]

    init(id: UUID = UUID(), name: String, weight: Double, date: Date? = nil, period: String = "10", grade: Double? = nil, calendarEventID: String? = nil, components: [EvaluationComponent] = []) {
        self.id = id
        self.name = name
        self.weight = weight
        self.date = date
        self.period = period
        self.grade = grade
        self.calendarEventID = calendarEventID
        self.components = components
    }

    // Decodificación tolerante: los datos guardados antes de existir los componentes siguen cargando
    enum CodingKeys: String, CodingKey {
        case id, name, weight, date, period, grade, calendarEventID, components
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        weight = try c.decode(Double.self, forKey: .weight)
        date = try c.decodeIfPresent(Date.self, forKey: .date)
        period = try c.decodeIfPresent(String.self, forKey: .period) ?? "10"
        grade = try c.decodeIfPresent(Double.self, forKey: .grade)
        calendarEventID = try c.decodeIfPresent(String.self, forKey: .calendarEventID)
        components = try c.decodeIfPresent([EvaluationComponent].self, forKey: .components) ?? []
    }

    var hasComponents: Bool { !components.isEmpty }

    var gradedComponentsCount: Int { components.filter { $0.grade != nil }.count }

    /// Nota real de la evaluación:
    /// - Sin componentes: la nota que se escribió a mano.
    /// - Con componentes: su media simple, solo cuando TODOS tienen nota (hasta entonces está pendiente).
    var effectiveGrade: Double? {
        guard hasComponents else { return grade }
        let grades = components.compactMap(\.grade)
        guard grades.count == components.count else { return nil }
        return grades.reduce(0, +) / Double(grades.count)
    }
}

enum FormulaMode: Int, Codable {
    case weightedAverage = 0
    case custom = 1
}

/// Propiedad libre que el usuario añade a una asignatura (nombre + valor)
struct CustomProperty: Identifiable, Codable, Hashable {
    var id = UUID()
    var name = ""
    var value = ""
}

struct Subject: Identifiable, Codable {
    let id: UUID
    var name: String
    var iconName: String
    var teacher: String
    var email: String
    var tutoringLocation: String
    var classroom: String
    var ects: Double
    var colorName: String
    var evaluations: [Evaluation]
    var customProperties: [CustomProperty]

    // Fórmula de la nota final
    var formulaMode: FormulaMode
    var customExpression: String
    var treatPendingAsZero: Bool

    var color: Color {
        Color(hex: colorName)
    }

    init(id: UUID = UUID(), name: String, iconName: String, teacher: String = "", email: String = "", tutoringLocation: String = "", classroom: String = "", ects: Double = 6.0, colorName: String = "#007AFF", evaluations: [Evaluation] = [], customProperties: [CustomProperty] = [], formulaMode: FormulaMode = .weightedAverage, customExpression: String = "Media", treatPendingAsZero: Bool = true) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.teacher = teacher
        self.email = email
        self.tutoringLocation = tutoringLocation
        self.classroom = classroom
        self.ects = ects
        self.colorName = colorName
        self.evaluations = evaluations
        self.customProperties = customProperties
        self.formulaMode = formulaMode
        self.customExpression = customExpression
        self.treatPendingAsZero = treatPendingAsZero
    }

    // Decodificación tolerante: los datos guardados antes de añadir la fórmula siguen cargando
    enum CodingKeys: String, CodingKey {
        case id, name, iconName, teacher, email, tutoringLocation, classroom, ects, colorName, evaluations, customProperties
        case formulaMode, customExpression, treatPendingAsZero
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        iconName = try c.decodeIfPresent(String.self, forKey: .iconName) ?? "book.fill"
        teacher = try c.decodeIfPresent(String.self, forKey: .teacher) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        tutoringLocation = try c.decodeIfPresent(String.self, forKey: .tutoringLocation) ?? ""
        classroom = try c.decodeIfPresent(String.self, forKey: .classroom) ?? ""
        ects = try c.decodeIfPresent(Double.self, forKey: .ects) ?? 6.0
        colorName = try c.decodeIfPresent(String.self, forKey: .colorName) ?? "#007AFF"
        evaluations = try c.decodeIfPresent([Evaluation].self, forKey: .evaluations) ?? []
        customProperties = try c.decodeIfPresent([CustomProperty].self, forKey: .customProperties) ?? []
        formulaMode = try c.decodeIfPresent(FormulaMode.self, forKey: .formulaMode) ?? .weightedAverage
        customExpression = try c.decodeIfPresent(String.self, forKey: .customExpression) ?? "Media"
        treatPendingAsZero = try c.decodeIfPresent(Bool.self, forKey: .treatPendingAsZero) ?? true
    }

    // MARK: Cálculo de la nota

    /// Media ponderada con los porcentajes de las evaluaciones.
    /// - Pendientes como 0: Σ(nota × peso / 100)
    /// - Pendientes ignoradas: Σ(nota × peso) / Σ(pesos de lo que ya tiene nota)
    var weightedAverage: Double {
        var weightedSum = 0.0
        var gradedWeight = 0.0
        for item in evaluations {
            if let g = item.effectiveGrade {
                weightedSum += g * item.weight
                gradedWeight += item.weight
            }
        }
        if treatPendingAsZero { return weightedSum / 100.0 }
        return gradedWeight > 0 ? weightedSum / gradedWeight : 0
    }

    /// Variables que se pueden usar en la fórmula personalizada
    func formulaVariables() -> FormulaVariables {
        var variables = FormulaVariables()
        variables.set("Media", value: weightedAverage)
        variables.set("MediaPonderada", value: weightedAverage)
        for item in evaluations {
            variables.set(item.name, value: item.effectiveGrade ?? (treatPendingAsZero ? 0 : nil))
        }
        return variables
    }

    /// Resultado de aplicar la fórmula elegida (sin redondear)
    func formulaResult() -> Result<Double, FormulaError> {
        switch formulaMode {
        case .weightedAverage:
            return .success(weightedAverage)
        case .custom:
            return FormulaEvaluator.evaluate(customExpression, variables: formulaVariables())
        }
    }

    /// Nota final mostrada en la app. Si la fórmula personalizada falla, usa la media ponderada.
    var calculatedGrade: Double {
        let raw = (try? formulaResult().get()) ?? weightedAverage
        return (raw * 100).rounded() / 100
    }

    /// Nota máxima que se podía haber conseguido con lo ya calificado:
    /// se sustituye la nota de cada evaluación calificada por 10 (las pendientes se
    /// tratan igual que en la nota real) y se aplica la misma fórmula.
    /// Ej.: una evaluación del 20 % ya calificada, con media ponderada → 2.
    /// Devuelve nil si todavía no hay ninguna evaluación calificada.
    var maxScoreSoFar: Double? {
        var best = self
        var anyGraded = false
        for index in best.evaluations.indices where best.evaluations[index].effectiveGrade != nil {
            best.evaluations[index].components = []
            best.evaluations[index].grade = 10
            anyGraded = true
        }
        guard anyGraded else { return nil }
        let raw = (try? best.formulaResult().get()) ?? best.weightedAverage
        return (raw * 100).rounded() / 100
    }
}

enum Weekday: String, CaseIterable, Identifiable, Codable {
    case monday = "Lunes"
    case tuesday = "Martes"
    case wednesday = "Miércoles"
    case thursday = "Jueves"
    case friday = "Viernes"

    var id: String { self.rawValue }

    /// Valor de `Calendar.component(.weekday)` (1 = domingo)
    var calendarValue: Int {
        switch self {
        case .monday: return 2
        case .tuesday: return 3
        case .wednesday: return 4
        case .thursday: return 5
        case .friday: return 6
        }
    }
}

struct ScheduleSlot: Identifiable, Codable {
    var id = UUID()
    var day: Weekday
    var subjectID: UUID
    var startTime: Date
    var endTime: Date
    var customClassroom: String?
}

extension ScheduleSlot {
    /// Minutos desde medianoche (ignora el día en el que se guardó el Date)
    var startMinutes: Int { Self.minutes(of: startTime) }
    var endMinutes: Int { Self.minutes(of: endTime) }

    private static func minutes(of date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

/// Un examen con fecha y sin nota: una evaluación suelta o un componente de una evaluación
struct UpcomingExamItem: Identifiable {
    let id: UUID
    let name: String
    let parentName: String?      // evaluación a la que pertenece (solo si es un componente)
    let subjectName: String
    let color: Color
    let date: Date
    let weight: Double           // % que aporta a la asignatura

    var subtitle: String {
        parentName.map { "\($0) • \(subjectName)" } ?? subjectName
    }
}

extension Subject {
    /// Exámenes pendientes con fecha. Cada componente cuenta como un examen y aporta
    /// peso de la evaluación ÷ nº de componentes (media simple).
    var scheduledExams: [UpcomingExamItem] {
        evaluations.flatMap { evaluation -> [UpcomingExamItem] in
            if evaluation.hasComponents {
                let share = evaluation.weight / Double(evaluation.components.count)
                return evaluation.components.compactMap { component in
                    guard component.grade == nil else { return nil }
                    return UpcomingExamItem(id: component.id, name: component.name, parentName: evaluation.name,
                                            subjectName: name, color: color, date: component.date, weight: share)
                }
            }
            guard evaluation.grade == nil, let date = evaluation.date else { return [] }
            return [UpcomingExamItem(id: evaluation.id, name: evaluation.name, parentName: nil,
                                     subjectName: name, color: color, date: date, weight: evaluation.weight)]
        }
    }
}

// MARK: VIEWMODEL PRINCIPAL
// @Observable: cada vista solo se redibuja si cambia lo que realmente lee.
// Cada operación hace UNA mutación y UN guardado (antes cada propiedad
// modificada disparaba su propio guardado completo en JSON).
@MainActor
@Observable
final class PlannerViewModel {
    private(set) var subjects: [Subject] = []
    private(set) var weeklySchedule: [ScheduleSlot] = []

    private static let subjectsKey = "PlannerSubjectsData_v1"
    private static let scheduleKey = "PlannerScheduleData_v1"

    init() {
        subjects = Self.load([Subject].self, key: Self.subjectsKey) ?? []
        weeklySchedule = Self.load([ScheduleSlot].self, key: Self.scheduleKey) ?? []
    }

    // MARK: Persistencia
    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            // Red de seguridad: conserva los datos originales antes de que se sobrescriban
            UserDefaults.standard.set(data, forKey: key + "_unreadable_backup")
            return nil
        }
    }

    private static func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func saveSubjects() { Self.save(subjects, key: Self.subjectsKey) }
    private func saveSchedule() { Self.save(weeklySchedule, key: Self.scheduleKey) }

    // MARK: Consultas
    func subject(withID id: UUID) -> Subject? {
        subjects.first { $0.id == id }
    }

    // MARK: Asignaturas
    func addSubject(name: String, iconName: String, teacher: String, email: String, tutoringLocation: String, classroom: String, ects: Double, colorName: String, customProperties: [CustomProperty] = []) {
        subjects.append(Subject(
            name: name,
            iconName: iconName,
            teacher: teacher,
            email: email,
            tutoringLocation: tutoringLocation,
            classroom: classroom,
            ects: ects,
            colorName: colorName,
            customProperties: customProperties
        ))
        saveSubjects()
    }

    func updateSubject(id: UUID, name: String, iconName: String, teacher: String, email: String, tutoringLocation: String, classroom: String, ects: Double, colorName: String, customProperties: [CustomProperty] = []) {
        modifySubject(id) {
            $0.name = name
            $0.iconName = iconName
            $0.teacher = teacher
            $0.email = email
            $0.tutoringLocation = tutoringLocation
            $0.classroom = classroom
            $0.ects = ects
            $0.colorName = colorName
            $0.customProperties = customProperties
        }
    }

    func updateFormula(subjectID: UUID, mode: FormulaMode, expression: String, treatPendingAsZero: Bool) {
        modifySubject(subjectID) {
            $0.formulaMode = mode
            $0.customExpression = expression.trimmingCharacters(in: .whitespacesAndNewlines)
            $0.treatPendingAsZero = treatPendingAsZero
        }
    }

    func deleteSubject(id: UUID) {
        guard let target = subject(withID: id) else { return }
        for evaluation in target.evaluations {
            removeCalendarEvents(of: evaluation)
        }
        subjects.removeAll { $0.id == id }
        weeklySchedule.removeAll { $0.subjectID == id }
        saveSubjects()
        saveSchedule()
    }

    private func modifySubject(_ id: UUID, _ change: (inout Subject) -> Void) {
        guard let index = subjects.firstIndex(where: { $0.id == id }) else { return }
        change(&subjects[index])
        saveSubjects()
    }

    // MARK: Horario semanal
    func addSlot(_ slot: ScheduleSlot) {
        weeklySchedule.append(slot)
        saveSchedule()
    }

    func updateSlot(_ slot: ScheduleSlot) {
        guard let index = weeklySchedule.firstIndex(where: { $0.id == slot.id }) else { return }
        weeklySchedule[index] = slot
        saveSchedule()
    }

    func deleteSlots(withIDs ids: [UUID]) {
        weeklySchedule.removeAll { ids.contains($0.id) }
        saveSchedule()
    }

    // MARK: Evaluaciones (con sincronización de calendario)
    func addEvaluation(to subjectID: UUID, _ evaluation: Evaluation) {
        guard let index = subjects.firstIndex(where: { $0.id == subjectID }) else { return }

        var created = evaluation
        created.calendarEventID = nil
        for i in created.components.indices { created.components[i].calendarEventID = nil }

        syncCalendar(&created, previous: nil, subjectName: subjects[index].name)
        subjects[index].evaluations.append(created)
        saveSubjects()
    }

    func updateEvaluation(in subjectID: UUID, _ evaluation: Evaluation) {
        guard let sIndex = subjects.firstIndex(where: { $0.id == subjectID }),
              let eIndex = subjects[sIndex].evaluations.firstIndex(where: { $0.id == evaluation.id }) else { return }

        let previous = subjects[sIndex].evaluations[eIndex]
        var updated = evaluation

        // Los identificadores de eventos del Calendario salen siempre de lo guardado
        updated.calendarEventID = previous.calendarEventID
        let previousEventIDs = Dictionary(previous.components.map { ($0.id, $0.calendarEventID) },
                                          uniquingKeysWith: { first, _ in first })
        for i in updated.components.indices {
            let componentID = updated.components[i].id
            updated.components[i].calendarEventID = previousEventIDs[componentID] ?? nil
        }

        syncCalendar(&updated, previous: previous, subjectName: subjects[sIndex].name)
        subjects[sIndex].evaluations[eIndex] = updated   // una sola mutación
        saveSubjects()
    }

    func deleteEvaluation(from subjectID: UUID, evaluationID: UUID) {
        guard let sIndex = subjects.firstIndex(where: { $0.id == subjectID }),
              let eIndex = subjects[sIndex].evaluations.firstIndex(where: { $0.id == evaluationID }) else { return }

        removeCalendarEvents(of: subjects[sIndex].evaluations[eIndex])
        subjects[sIndex].evaluations.remove(at: eIndex)
        saveSubjects()
    }

    // MARK: Calendario
    /// Deja el Calendario igual que la evaluación: un evento propio, o uno por componente.
    /// Si hay componentes, la evaluación pierde su fecha y su nota manual.
    private func syncCalendar(_ evaluation: inout Evaluation, previous: Evaluation?, subjectName: String) {
        let calendar = CalendarSyncManager.shared

        if evaluation.hasComponents {
            evaluation.date = nil
            evaluation.grade = nil

            // El evento propio deja de existir
            calendar.deleteEvent(identifier: previous?.calendarEventID)
            evaluation.calendarEventID = nil

            // Componentes eliminados
            let keptIDs = Set(evaluation.components.map(\.id))
            for old in previous?.components ?? [] where !keptIDs.contains(old.id) {
                calendar.deleteEvent(identifier: old.calendarEventID)
            }

            // Componentes nuevos o modificados
            for i in evaluation.components.indices {
                let component = evaluation.components[i]
                evaluation.components[i].calendarEventID = calendar.upsertEvent(
                    identifier: component.calendarEventID,
                    title: Self.componentTitle(subjectName, evaluation.name, component.name),
                    date: component.date,
                    notes: Self.examNotes(subjectName, evaluation.weight)
                )
            }
        } else {
            // Si antes tenía componentes, fuera sus eventos
            for old in previous?.components ?? [] {
                calendar.deleteEvent(identifier: old.calendarEventID)
            }

            if let date = evaluation.date {
                evaluation.calendarEventID = calendar.upsertEvent(
                    identifier: evaluation.calendarEventID,
                    title: Self.examTitle(subjectName, evaluation.name),
                    date: date,
                    notes: Self.examNotes(subjectName, evaluation.weight)
                )
            } else if evaluation.calendarEventID != nil {
                calendar.deleteEvent(identifier: evaluation.calendarEventID)
                evaluation.calendarEventID = nil
            }
        }
    }

    private func removeCalendarEvents(of evaluation: Evaluation) {
        CalendarSyncManager.shared.deleteEvent(identifier: evaluation.calendarEventID)
        for component in evaluation.components {
            CalendarSyncManager.shared.deleteEvent(identifier: component.calendarEventID)
        }
    }

    private static func examTitle(_ subject: String, _ evaluation: String) -> String {
        "\(subject): \(evaluation)"
    }

    private static func componentTitle(_ subject: String, _ evaluation: String, _ component: String) -> String {
        "\(subject): \(evaluation) · \(component)"
    }

    private static func examNotes(_ subject: String, _ weight: Double) -> String {
        "Examen de \(subject). Peso: \(weight.compactText)%"
    }
}
