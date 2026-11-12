import SwiftUI

// MARK: DASHBOARD VIEW
struct DashboardView: View {
    let viewModel: PlannerViewModel
    let timerManager: StudyTimerManager

    @Environment(\.scenePhase) private var scenePhase
    @State private var now = Date()
    @State private var showingAddSubject = false
    @State private var showingTimer = false
    @State private var subjectToEdit: Subject?
    @State private var subjectToDelete: Subject?

    var body: some View {
        let todaySlots = remainingSlotsToday
        let nextExams = nextExamDay

        List {
            // SECCIÓN 1: CLASES QUE QUEDAN HOY (se oculta si no queda ninguna)
            if !todaySlots.isEmpty {
                Section("Clases de hoy") {
                    ForEach(todaySlots) { slot in
                        if let subject = viewModel.subject(withID: slot.subjectID) {
                            ScheduleSlotRow(slot: slot, subject: subject)
                        }
                    }
                }
            }

            // SECCIÓN 2: PRÓXIMO EXAMEN
            Section("Próximo examen") {
                if nextExams.isEmpty {
                    ContentUnavailableView(
                        "Sin exámenes pendientes",
                        systemImage: "checkmark.seal.fill",
                        description: Text("Añade evaluaciones con fecha en tus asignaturas para verlas aquí.")
                    )
                } else {
                    ForEach(nextExams) { item in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(item.color)
                                .frame(width: 12, height: 12)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(.headline)
                                Text("\(item.subtitle) • \(examDateText(item.date))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(item.weight.compactText)%")
                                .font(.subheadline)
                                .bold()
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(item.color.opacity(0.15))
                                .foregroundStyle(item.color)
                                .clipShape(Capsule())
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            // SECCIÓN 3: MIS ASIGNATURAS
            Section("Mis asignaturas") {
                if viewModel.subjects.isEmpty {
                    ContentUnavailableView(
                        "Sin asignaturas",
                        systemImage: "books.vertical",
                        description: Text("Pulsa + para añadir tu primera asignatura.")
                    )
                }
                ForEach(viewModel.subjects) { subject in
                    NavigationLink(value: subject.id) {
                        SubjectRow(subject: subject)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            subjectToDelete = subject
                        } label: {
                            Label("Eliminar", systemImage: "trash")
                        }
                        Button {
                            subjectToEdit = subject
                        } label: {
                            Label("Editar", systemImage: "pencil")
                        }
                        .tint(.orange)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Planner")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: UUID.self) { subjectID in
            SubjectDetailView(subjectID: subjectID, viewModel: viewModel)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingTimer = true
                } label: {
                    Label("Temporizador de estudio", systemImage: timerManager.isRunning ? "timer.circle.fill" : "timer")
                }
                .tint(timerManager.isRunning ? .green : nil)
                .popover(isPresented: $showingTimer) {
                    StudyTimerPopover(timerManager: timerManager)
                        .presentationCompactAdaptation(.popover)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddSubject = true
                } label: {
                    Label("Añadir asignatura", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSubject) {
            SubjectFormView(viewModel: viewModel)
        }
        .sheet(item: $subjectToEdit) { subject in
            SubjectFormView(viewModel: viewModel, subject: subject)
        }
        .confirmationDialog(
            "¿Eliminar asignatura?",
            isPresented: Binding(
                get: { subjectToDelete != nil },
                set: { if !$0 { subjectToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: subjectToDelete
        ) { subject in
            Button("Eliminar «\(subject.name)»", role: .destructive) {
                viewModel.deleteSubject(id: subject.id)
            }
        } message: { _ in
            Text("Se borrarán también sus evaluaciones, sus clases del horario y sus exámenes del calendario.")
        }
        // Mantiene "ahora" al día: las clases ya terminadas desaparecen solas
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    // MARK: Datos
    /// Clases de hoy que aún no han terminado
    private var remainingSlotsToday: [ScheduleSlot] {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: now)
        guard let today = Weekday.allCases.first(where: { $0.calendarValue == weekday }) else { return [] }

        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let nowMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)

        return viewModel.weeklySchedule
            .filter { $0.day == today && $0.endMinutes > nowMinutes }
            .sorted { $0.startMinutes < $1.startMinutes }
    }

    /// Exámenes del primer día con exámenes por venir (evaluaciones sueltas y componentes).
    /// Los ya pasados no cuentan.
    private var nextExamDay: [UpcomingExamItem] {
        let upcoming = viewModel.subjects
            .flatMap(\.scheduledExams)
            .filter { $0.date >= now }
            .sorted { $0.date < $1.date }

        guard let firstDate = upcoming.first?.date else { return [] }
        let calendar = Calendar.current
        return upcoming.filter { calendar.isDate($0.date, inSameDayAs: firstDate) }
    }

    private func examDateText(_ date: Date?) -> String {
        guard let date else { return "Sin fecha" }
        return date.formatted(date: .long, time: .shortened)
    }
}

// MARK: FILA DE ASIGNATURA
private struct SubjectRow: View {
    let subject: Subject

    var body: some View {
        let grade = subject.calculatedGrade

        HStack(spacing: 16) {
            Image(systemName: subject.iconName)
                .font(.title)
                .foregroundStyle(subject.color)
                .frame(width: 48, height: 48)
                .background(subject.color.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(subject.name)
                    .font(.title3)
                    .bold()
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(grade.gradeText)
                    .font(.title3)
                    .bold()
                    .foregroundStyle(grade >= 5.0 ? .green : .red)
                if let maxScore = subject.maxScoreSoFar {
                    Text("/ \(maxScore.flexibleText)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var subtitle: String {
        let ects = "\(subject.ects.compactText) ECTS"
        return subject.teacher.isEmpty ? ects : "\(ects) • Prof. \(subject.teacher)"
    }
}

// MARK: FILA DE CLASE (compartida por Dashboard y Horario)
struct ScheduleSlotRow: View {
    let slot: ScheduleSlot
    let subject: Subject

    private var classroom: String { slot.customClassroom ?? subject.classroom }

    var body: some View {
        HStack(spacing: 12) {
            Capsule()
                .fill(subject.color)
                .frame(width: 4, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(subject.name)
                    .font(.headline)
                Text("\(slot.startTime.formatted(date: .omitted, time: .shortened)) – \(slot.endTime.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !classroom.isEmpty {
                Text(classroom)
                    .font(.caption)
                    .bold()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.12))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: HORARIO CONFIG (AÑADIR / EDITAR / ELIMINAR CLASES)
struct ScheduleConfigView: View {
    let viewModel: PlannerViewModel
    @State private var selectedDay: Weekday = .monday
    @State private var activeSheet: SlotSheet?

    private enum SlotSheet: Identifiable {
        case add
        case edit(ScheduleSlot)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let slot): return slot.id.uuidString
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Día", selection: $selectedDay) {
                ForEach(Weekday.allCases) { day in
                    Text(day.rawValue).tag(day)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            List {
                Section {
                    let daySlots = currentDaySlots
                    if daySlots.isEmpty {
                        ContentUnavailableView(
                            "Sin clases los \(selectedDay.rawValue.lowercased())",
                            systemImage: "calendar.badge.clock",
                            description: Text("Pulsa + para añadir una clase a este día.")
                        )
                    } else {
                        ForEach(daySlots) { slot in
                            if let subject = viewModel.subjects.first(where: { $0.id == slot.subjectID }) {
                                Button {
                                    activeSheet = .edit(slot)
                                } label: {
                                    ScheduleSlotRow(slot: slot, subject: subject)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        viewModel.deleteSlots(withIDs: [slot.id])
                                    } label: {
                                        Label("Eliminar", systemImage: "trash")
                                    }
                                    Button {
                                        activeSheet = .edit(slot)
                                    } label: {
                                        Label("Editar", systemImage: "pencil")
                                    }
                                    .tint(.orange)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Horario del \(selectedDay.rawValue)")
                }
            }
            .listStyle(.insetGrouped)
        }
        .navigationTitle("Horario Semanal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    activeSheet = .add
                } label: {
                    Label("Añadir clase", systemImage: "plus")
                }
                .disabled(viewModel.subjects.isEmpty)
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .add:
                SlotFormView(viewModel: viewModel, day: selectedDay)
            case .edit(let slot):
                SlotFormView(viewModel: viewModel, day: slot.day, slot: slot)
            }
        }
    }

    private var currentDaySlots: [ScheduleSlot] {
        viewModel.weeklySchedule
            .filter { $0.day == selectedDay }
            .sorted { $0.startMinutes < $1.startMinutes }
    }
}

// MARK: FORMULARIO DE CLASE (CREAR Y EDITAR)
struct SlotFormView: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: PlannerViewModel

    private let existingSlot: ScheduleSlot?
    @State private var day: Weekday
    @State private var subjectID: UUID?
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var customClassroom: String

    init(viewModel: PlannerViewModel, day: Weekday, slot: ScheduleSlot? = nil) {
        self.viewModel = viewModel
        self.existingSlot = slot
        _day = State(initialValue: slot?.day ?? day)
        _subjectID = State(initialValue: slot?.subjectID ?? viewModel.subjects.first?.id)
        _startTime = State(initialValue: slot?.startTime ?? Date())
        _endTime = State(initialValue: slot?.endTime ?? Date().addingTimeInterval(3600))
        _customClassroom = State(initialValue: slot?.customClassroom ?? "")
    }

    private var isEditing: Bool { existingSlot != nil }

    private func minutes(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private var hasValidTimes: Bool { minutes(endTime) > minutes(startTime) }
    private var canSave: Bool { subjectID != nil && hasValidTimes }

    var body: some View {
        NavigationStack {
            Form {
                Section("Clase") {
                    Picker("Asignatura", selection: $subjectID) {
                        ForEach(viewModel.subjects) { sub in
                            Text(sub.name).tag(UUID?.some(sub.id))
                        }
                    }
                    Picker("Día", selection: $day) {
                        ForEach(Weekday.allCases) { d in
                            Text(d.rawValue).tag(d)
                        }
                    }
                }

                Section {
                    DatePicker("Hora de inicio", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("Hora de fin", selection: $endTime, displayedComponents: .hourAndMinute)
                } header: {
                    Text("Horario")
                } footer: {
                    if !hasValidTimes {
                        Text("La hora de fin debe ser posterior a la de inicio.")
                            .foregroundStyle(.red)
                    }
                }

                Section("Aula (opcional)") {
                    TextField("Aula específica (ej: Lab 201)", text: $customClassroom)
                }

                if isEditing, let slot = existingSlot {
                    Section {
                        Button("Eliminar clase", role: .destructive) {
                            viewModel.deleteSlots(withIDs: [slot.id])
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Editar clase" : "Nueva clase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        save()
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        guard let subjectID else { return }
        let trimmed = customClassroom.trimmingCharacters(in: .whitespaces)
        let slot = ScheduleSlot(
            id: existingSlot?.id ?? UUID(),
            day: day,
            subjectID: subjectID,
            startTime: startTime,
            endTime: endTime,
            customClassroom: trimmed.isEmpty ? nil : trimmed
        )
        if isEditing {
            viewModel.updateSlot(slot)
        } else {
            viewModel.addSlot(slot)
        }
    }
}

// MARK: FORMULARIO DE ASIGNATURA (CREAR Y EDITAR)
struct SubjectFormView: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: PlannerViewModel
    private let subject: Subject?

    @State private var name: String
    @State private var teacher: String
    @State private var email: String
    @State private var tutoringLocation: String
    @State private var classroom: String
    @State private var ectsText: String
    @State private var color: Color
    @State private var iconName: String
    @State private var showsExtraInfo: Bool
    @State private var customProperties: [CustomProperty]

    init(viewModel: PlannerViewModel, subject: Subject? = nil) {
        self.viewModel = viewModel
        self.subject = subject
        _name = State(initialValue: subject?.name ?? "")
        _teacher = State(initialValue: subject?.teacher ?? "")
        _email = State(initialValue: subject?.email ?? "")
        _tutoringLocation = State(initialValue: subject?.tutoringLocation ?? "")
        _classroom = State(initialValue: subject?.classroom ?? "")
        _ectsText = State(initialValue: (subject?.ects ?? 6).compactText)
        _color = State(initialValue: subject?.color ?? .blue)
        _iconName = State(initialValue: subject?.iconName ?? "book.fill")
        _customProperties = State(initialValue: subject?.customProperties ?? [])
        _showsExtraInfo = State(initialValue: subject.map {
            !$0.teacher.isEmpty || !$0.email.isEmpty || !$0.classroom.isEmpty || !$0.tutoringLocation.isEmpty
        } ?? false)
    }

    private var isEditing: Bool { subject != nil }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Asignatura") {
                    TextField("Nombre de la materia", text: $name)
                    LabeledContent("Créditos ECTS") {
                        TextField("6", text: $ectsText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    ColorPicker("Color", selection: $color, supportsOpacity: false)
                }

                Section("Icono") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 48))], spacing: 12) {
                        ForEach(availableSubjectIcons, id: \.0) { icon in
                            Button {
                                iconName = icon.0
                            } label: {
                                Image(systemName: icon.0)
                                    .font(.title2)
                                    .foregroundStyle(iconName == icon.0 ? color : .gray)
                                    .frame(width: 46, height: 46)
                                    .background(iconName == icon.0 ? color.opacity(0.2) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(iconName == icon.0 ? color : Color.clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(icon.1)
                            .accessibilityAddTraits(iconName == icon.0 ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    DisclosureGroup("Contacto y aula (opcional)", isExpanded: $showsExtraInfo) {
                        TextField("Profesor", text: $teacher)
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Aula", text: $classroom)
                        TextField("Tutorías", text: $tutoringLocation)
                    }
                }

                Section("Propiedades personalizadas") {
                    ForEach($customProperties) { $property in
                        HStack(spacing: 12) {
                            TextField("Nombre", text: $property.name)
                            TextField("Valor", text: $property.value)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { customProperties.remove(atOffsets: $0) }

                    Button {
                        customProperties.append(CustomProperty())
                    } label: {
                        Label("Añadir propiedad", systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle(isEditing ? "Editar Asignatura" : "Nueva Asignatura")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Actualizar" : "Guardar") { save() }
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    private func save() {
        let ects = ectsText.decimalValue ?? subject?.ects ?? 6
        // Se descartan las propiedades sin nombre
        let cleanedProperties = customProperties.compactMap { property -> CustomProperty? in
            let name = property.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return CustomProperty(
                id: property.id,
                name: name,
                value: property.value.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        if let subject {
            viewModel.updateSubject(
                id: subject.id,
                name: trimmedName,
                iconName: iconName,
                teacher: teacher,
                email: email,
                tutoringLocation: tutoringLocation,
                classroom: classroom,
                ects: ects,
                colorName: color.toHex(),
                customProperties: cleanedProperties
            )
        } else {
            viewModel.addSubject(
                name: trimmedName,
                iconName: iconName,
                teacher: teacher,
                email: email,
                tutoringLocation: tutoringLocation,
                classroom: classroom,
                ects: ects,
                colorName: color.toHex(),
                customProperties: cleanedProperties
            )
        }
        dismiss()
    }
}

// MARK: COLECCIÓN DE ICONOS DISPONIBLES
let availableSubjectIcons = [
    ("book.fill", "General"),
    ("function", "Cálculo"),
    ("x.squareroot", "Álgebra"),
    ("atom", "Física"),
    ("flask.fill", "Química"),
    ("leaf.fill", "Biología"),
    ("desktopcomputer", "Informática"),
    ("cpu", "Hardware"),
    ("network", "Redes"),
    ("terminal.fill", "Sistemas"),
    ("bolt.fill", "Electricidad"),
    ("gearshape.fill", "Mecánica"),
    ("wrench.and.screwdriver.fill", "Taller"),
    ("paintpalette.fill", "Arte/Diseño"),
    ("pencil.and.outline", "Dibujo"),
    ("camera.fill", "Audiovisual"),
    ("globe.americas.fill", "Geografía"),
    ("text.book.closed.fill", "Lengua/Lit"),
    ("a.square.fill", "Idiomas"),
    ("building.columns.fill", "Historia"),
    ("doc.text.fill", "Derecho"),
    ("stethoscope", "Medicina"),
    ("cross.case.fill", "Salud"),
    ("pill.fill", "Farmacia"),
    ("cross.vial.fill", "Laboratorio"),
    ("waveform.path.ecg", "Biomédica"),
    ("brain.head.profile", "Psicología"),
    ("chart.bar.fill", "Estadística"),
    ("chart.pie.fill", "Finanzas"),
    ("number.square.fill", "Mates/Eco"),
    ("briefcase.fill", "Empresa"),
    ("lightbulb.fill", "Filosofía"),
    ("person.3.fill", "Sociología"),
    ("music.note", "Música"),
    ("theatermasks.fill", "Teatro"),
    ("figure.run", "Deporte"),
    ("map.fill", "Topografía"),
    ("antenna.radiowaves.left.and.right", "Telecom"),
    ("shield.checkerboard", "Ciberseguridad"),
    ("eye.fill", "Óptica")
]
