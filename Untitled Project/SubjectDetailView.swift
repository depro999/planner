import SwiftUI

// MARK: VISTA DETALLE DE LA ASIGNATURA
struct SubjectDetailView: View {
    let subjectID: UUID
    let viewModel: PlannerViewModel

    @State private var showingFormulaSheet = false
    @State private var showingAddEvaluation = false
    @State private var evaluationToEdit: Evaluation?
    @State private var showsMoreProperties = false

    var body: some View {
        if let subject = viewModel.subject(withID: subjectID) {
            content(for: subject)
        } else {
            ContentUnavailableView("Asignatura no encontrada", systemImage: "questionmark.folder")
        }
    }

    private func content(for subject: Subject) -> some View {
        let grade = subject.calculatedGrade
        let totalWeight = subject.evaluations.reduce(0) { $0 + $1.weight }

        return List {
            // MARK: BANNER Y ENCABEZADO
            Section {
                HStack(spacing: 16) {
                    Image(systemName: subject.iconName)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(subject.color)
                        .frame(width: 60, height: 60)
                        .background(subject.color.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(subject.name)
                            .font(.largeTitle)
                            .bold()
                            .minimumScaleFactor(0.6)
                        HStack {
                            Text("Nota final:")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(grade.gradeText)
                                .font(.title3)
                                .bold()
                                .foregroundStyle(grade >= 5.0 ? .green : .red)
                            if let maxScore = subject.maxScoreSoFar {
                                Text("/ \(maxScore.flexibleText)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            // MARK: PROPIEDADES (solo se muestran las que tienen valor)
            Section("Propiedades") {
                if !subject.teacher.isEmpty {
                    property("Profesor", systemImage: "person.fill", value: subject.teacher)
                }
                if !subject.email.isEmpty {
                    LabeledContent {
                        if let url = URL(string: "mailto:\(subject.email)") {
                            Link(subject.email, destination: url)
                        } else {
                            Text(subject.email)
                        }
                    } label: {
                        Label("Email", systemImage: "envelope.fill")
                    }
                }
                if !subject.tutoringLocation.isEmpty {
                    property("Tutorías", systemImage: "mappin.and.ellipse", value: subject.tutoringLocation)
                }
                ForEach(subject.customProperties) { custom in
                    property(custom.name, systemImage: "tag.fill", value: custom.value.isEmpty ? "—" : custom.value)
                }

                DisclosureGroup("Más propiedades", isExpanded: $showsMoreProperties) {
                    if !subject.classroom.isEmpty {
                        property("Clase", systemImage: "building.2.fill", value: subject.classroom)
                    }
                    property("ECTS", systemImage: "graduationcap.fill", value: "\(subject.ects.compactText) ECTS")

                    Button {
                        showingFormulaSheet = true
                    } label: {
                        HStack {
                            Label("Fórmula", systemImage: "function")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(subject.formulaMode == .weightedAverage ? "Media ponderada" : "Personalizada")
                                .bold()
                                .foregroundStyle(.blue)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // MARK: TABLA DE EVALUACIONES Y NOTAS
            Section {
                if subject.evaluations.isEmpty {
                    Text("No hay evaluaciones registradas en esta materia.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(subject.evaluations) { evaluation in
                        Button {
                            evaluationToEdit = evaluation
                        } label: {
                            EvaluationRow(evaluation: evaluation)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                viewModel.deleteEvaluation(from: subject.id, evaluationID: evaluation.id)
                            } label: {
                                Label("Eliminar", systemImage: "trash")
                            }
                        }
                    }
                }

                Button {
                    showingAddEvaluation = true
                } label: {
                    Label("Añadir evaluación", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Notas")
            } footer: {
                if !subject.evaluations.isEmpty, abs(totalWeight - 100) > 0.01 {
                    Text("Los pesos suman \(totalWeight.compactText)%. Deberían sumar 100%.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(subject.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingFormulaSheet) {
            FormulaConfigView(viewModel: viewModel, subjectID: subject.id)
        }
        .sheet(isPresented: $showingAddEvaluation) {
            EvaluationFormView(viewModel: viewModel, subjectID: subject.id)
        }
        .sheet(item: $evaluationToEdit) { evaluation in
            EvaluationFormView(viewModel: viewModel, subjectID: subject.id, evaluation: evaluation)
        }
    }

    private func property(_ title: String, systemImage: String, value: String) -> some View {
        LabeledContent {
            Text(value)
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}

// MARK: FILA DE EVALUACIÓN
private struct EvaluationRow: View {
    let evaluation: Evaluation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(evaluation.name)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                gradeLabel
            }

            // Componentes (si los hay): fecha y nota de cada uno
            if evaluation.hasComponents {
                ForEach(evaluation.components) { component in
                    HStack {
                        Text(component.name)
                        Spacer()
                        Text(component.date, format: .dateTime.day().month(.abbreviated))
                        Text(component.grade?.gradeText ?? "–")
                            .monospacedDigit()
                            .frame(minWidth: 40, alignment: .trailing)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var gradeLabel: some View {
        if let grade = evaluation.effectiveGrade {
            Text(grade.gradeText)
                .font(.title3)
                .bold()
                .foregroundStyle(grade >= 5.0 ? .green : .red)
        } else if evaluation.hasComponents {
            Text("\(evaluation.gradedComponentsCount)/\(evaluation.components.count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            Text("–")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        let weight = "Peso: \(evaluation.weight.compactText)%"
        if evaluation.hasComponents {
            let count = evaluation.components.count
            return "\(weight) • \(count == 1 ? "1 componente" : "\(count) componentes")"
        }
        let date = evaluation.date?.formatted(date: .numeric, time: .shortened) ?? "Sin fecha"
        return "\(weight) • Fecha: \(date)"
    }
}

// MARK: CONFIGURADOR DE FÓRMULA DE CÁLCULO
struct FormulaConfigView: View {
    @Environment(\.dismiss) var dismiss
    let viewModel: PlannerViewModel
    let subjectID: UUID
    
    @State private var mode: FormulaMode = .weightedAverage
    @State private var expression: String = "Media"
    @State private var treatPendingAsZero: Bool = true
    @State private var didLoad = false
    
    private var subject: Subject? {
        viewModel.subjects.first(where: { $0.id == subjectID })
    }
    
    /// Copia de la asignatura con la fórmula que se está editando (para la vista previa en vivo)
    private var draft: Subject? {
        guard var copy = subject else { return nil }
        copy.formulaMode = mode
        copy.customExpression = expression
        copy.treatPendingAsZero = treatPendingAsZero
        return copy
    }
    
    private var result: Result<Double, FormulaError>? {
        draft?.formulaResult()
    }
    
    private var hasError: Bool {
        if case .failure = result { return mode == .custom }
        return false
    }
    
    private var totalWeight: Double {
        subject?.evaluations.reduce(0) { $0 + $1.weight } ?? 0
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Modo de cálculo") {
                    Picker("Fórmula", selection: $mode) {
                        Text("Media ponderada").tag(FormulaMode.weightedAverage)
                        Text("Personalizada").tag(FormulaMode.custom)
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 4)
                }
                
                if mode == .weightedAverage {
                    Section {
                        Text("Nota = Σ(Nota_i × Peso_i / 100)")
                            .font(.system(.subheadline, design: .monospaced))
                            .bold()
                            .foregroundStyle(.blue)
                        LabeledContent("Suma de los pesos") {
                            Text("\(totalWeight, format: .number.precision(.fractionLength(0...1)))%")
                                .foregroundStyle(abs(totalWeight - 100) < 0.01 ? Color.green : Color.orange)
                        }
                    } header: {
                        Text("Fórmula estándar")
                    } footer: {
                        Text("Multiplica cada nota por su porcentaje de peso en la tabla de evaluaciones y las suma.")
                    }
                } else {
                    Section {
                        TextField("Expresión", text: $expression, axis: .vertical)
                            .font(.system(.body, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                insertButton("Media", systemImage: "percent")
                                ForEach(subject?.evaluations ?? []) { item in
                                    let id = FormulaEvaluator.identifier(for: item.name)
                                    if !id.isEmpty {
                                        insertButton(id)
                                    }
                                }
                                insertButton("min(", tint: .blue)
                                insertButton("max(", tint: .purple)
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text("Expresión personalizada")
                    } footer: {
                        Text("Operadores + − * / ^ y paréntesis. min(a, b, …) y max(a, b, …) devuelven el menor o el mayor de todos los valores que pongas. «Media» es la media ponderada con los porcentajes de tus evaluaciones; el resto de variables son los nombres de las evaluaciones (sin espacios). Decimales con punto: 0.6")
                    }
                }
                
                Section {
                    Toggle("Tratar pendientes como 0", isOn: $treatPendingAsZero)
                } footer: {
                    Text(treatPendingAsZero
                         ? "Las evaluaciones sin nota cuentan como un 0."
                         : "La media se calcula solo con las evaluaciones que ya tienen nota. En la fórmula personalizada, usar una evaluación sin nota da error.")
                }
                
                Section("Vista previa") {
                    if let subject {
                        switch result {
                        case .success(let value)?:
                            LabeledContent("Nota calculada (\(subject.name))") {
                                Text(value, format: .number.precision(.fractionLength(2)))
                                    .font(.title2)
                                    .bold()
                                    .foregroundStyle(value >= 5.0 ? .green : .red)
                            }
                        case .failure(let error)?:
                            if mode == .custom {
                                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(.orange)
                            }
                        case nil:
                            EmptyView()
                        }
                        
                        if mode == .custom {
                            LabeledContent("Media ponderada") {
                                Text(draft?.weightedAverage ?? 0, format: .number.precision(.fractionLength(2)))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Configurar fórmula")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                guard !didLoad, let subject else { return }
                didLoad = true
                mode = subject.formulaMode
                expression = subject.customExpression
                treatPendingAsZero = subject.treatPendingAsZero
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        viewModel.updateFormula(
                            subjectID: subjectID,
                            mode: mode,
                            expression: expression,
                            treatPendingAsZero: treatPendingAsZero
                        )
                        dismiss()
                    }
                    .disabled(hasError)
                }
            }
        }
    }
    
    private func insertButton(_ text: String, systemImage: String? = nil, tint: Color = .accentColor) -> some View {
        Button {
            expression += text
        } label: {
            if let systemImage {
                Label(text, systemImage: systemImage)
            } else {
                Text(text)
            }
        }
        .font(.caption)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(tint)
    }
}

// MARK: FORMULARIO DE EVALUACIÓN (CREAR Y EDITAR)
// Una evaluación puede tener fecha y nota propias, o dividirse en componentes
// (cada uno con nombre, fecha y nota). En ese caso la nota es la media simple
// de los componentes y la evaluación no tiene fecha propia.
struct EvaluationFormView: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: PlannerViewModel
    let subjectID: UUID
    private let evaluation: Evaluation?

    @State private var name: String
    @State private var weightText: String
    @State private var hasDate: Bool
    @State private var date: Date
    @State private var gradeText: String
    @State private var usesComponents: Bool
    @State private var components: [EvaluationComponent]
    @State private var componentDraft: EvaluationComponent?

    init(viewModel: PlannerViewModel, subjectID: UUID, evaluation: Evaluation? = nil) {
        self.viewModel = viewModel
        self.subjectID = subjectID
        self.evaluation = evaluation
        _name = State(initialValue: evaluation?.name ?? "")
        _weightText = State(initialValue: (evaluation?.weight ?? 20).compactText)
        _hasDate = State(initialValue: evaluation?.date != nil)
        _date = State(initialValue: evaluation?.date ?? Date())
        _gradeText = State(initialValue: evaluation?.grade?.gradeText ?? "")
        _usesComponents = State(initialValue: evaluation?.hasComponents ?? false)
        _components = State(initialValue: evaluation?.components ?? [])
    }

    private var isEditing: Bool { evaluation != nil }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Peso válido (0–100) o nil
    private var weight: Double? {
        guard let value = weightText.decimalValue, (0...100).contains(value) else { return nil }
        return value
    }

    private var trimmedGrade: String { gradeText.trimmingCharacters(in: .whitespaces) }
    private var grade: Double? { trimmedGrade.decimalValue }
    private var gradeIsValid: Bool {
        trimmedGrade.isEmpty || (grade.map { (0...10).contains($0) } ?? false)
    }

    private var canSave: Bool {
        guard !trimmedName.isEmpty, weight != nil else { return false }
        return usesComponents ? !components.isEmpty : gradeIsValid
    }

    /// Nota que saldría ahora mismo con los componentes actuales
    private var componentsMean: Double? {
        Evaluation(name: "", weight: 0, components: components).effectiveGrade
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre (ej: Evaluación continua)", text: $name)
                    LabeledContent("Peso (%)") {
                        TextField("20", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Evaluación")
                } footer: {
                    if weight == nil {
                        Text("El peso debe estar entre 0 y 100.")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Toggle("Dividir en componentes", isOn: $usesComponents.animation())
                } footer: {
                    Text(usesComponents
                         ? "La nota será la media de los componentes y la evaluación no tendrá fecha propia."
                         : "Actívalo si la nota sale de varias partes (parciales, prácticas…).")
                }

                if usesComponents {
                    Section {
                        ForEach(components) { component in
                            Button {
                                componentDraft = component
                            } label: {
                                ComponentRow(component: component)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { components.remove(atOffsets: $0) }

                        Button {
                            componentDraft = EvaluationComponent(name: "", date: Date())
                        } label: {
                            Label("Añadir componente", systemImage: "plus.circle.fill")
                        }
                    } header: {
                        Text("Componentes")
                    } footer: {
                        componentsFooter
                    }
                } else {
                    Section("Fecha del examen") {
                        Toggle("Asignar fecha", isOn: $hasDate)
                        if hasDate {
                            DatePicker("Fecha y hora", selection: $date, displayedComponents: [.date, .hourAndMinute])
                        }
                    }

                    Section {
                        TextField("Nota (0 - 10)", text: $gradeText)
                            .keyboardType(.decimalPad)
                    } header: {
                        Text("Calificación (opcional)")
                    } footer: {
                        if !gradeIsValid {
                            Text("La nota debe estar entre 0 y 10.")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Editar Evaluación" : "Nueva Evaluación")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Actualizar" : "Guardar") { save() }
                        .disabled(!canSave)
                }
            }
            .sheet(item: $componentDraft) { draft in
                ComponentFormView(component: draft) { saved in
                    if let index = components.firstIndex(where: { $0.id == saved.id }) {
                        components[index] = saved
                    } else {
                        components.append(saved)
                    }
                    components.sort { $0.date < $1.date }
                }
            }
        }
    }

    @ViewBuilder
    private var componentsFooter: some View {
        if components.isEmpty {
            Text("Añade al menos un componente.")
        } else if let mean = componentsMean {
            Text("Nota de la evaluación: \(mean.gradeText) (media simple).")
        } else {
            Text("La nota se calculará cuando todos los componentes tengan nota.")
        }
    }

    private func save() {
        guard let weight else { return }

        let result = Evaluation(
            id: evaluation?.id ?? UUID(),
            name: trimmedName,
            weight: weight,
            date: usesComponents ? nil : (hasDate ? date : nil),
            period: evaluation?.period ?? "10",
            grade: usesComponents ? nil : grade,
            calendarEventID: evaluation?.calendarEventID,
            components: usesComponents ? components : []
        )

        if isEditing {
            viewModel.updateEvaluation(in: subjectID, result)
        } else {
            viewModel.addEvaluation(to: subjectID, result)
        }
        dismiss()
    }
}

// MARK: FILA DE COMPONENTE (dentro del formulario)
private struct ComponentRow: View {
    let component: EvaluationComponent

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(component.name)
                Text(component.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(component.grade?.gradeText ?? "–")
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

// MARK: FORMULARIO DE COMPONENTE (nombre, fecha y nota opcional)
struct ComponentFormView: View {
    @Environment(\.dismiss) private var dismiss
    private let original: EvaluationComponent
    private let onSave: (EvaluationComponent) -> Void

    @State private var name: String
    @State private var date: Date
    @State private var gradeText: String

    init(component: EvaluationComponent, onSave: @escaping (EvaluationComponent) -> Void) {
        original = component
        self.onSave = onSave
        _name = State(initialValue: component.name)
        _date = State(initialValue: component.date)
        _gradeText = State(initialValue: component.grade?.gradeText ?? "")
    }

    private var isNew: Bool { original.name.isEmpty }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedGrade: String { gradeText.trimmingCharacters(in: .whitespaces) }
    private var grade: Double? { trimmedGrade.decimalValue }
    private var gradeIsValid: Bool {
        trimmedGrade.isEmpty || (grade.map { (0...10).contains($0) } ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Componente") {
                    TextField("Nombre (ej: Test 1)", text: $name)
                    DatePicker("Fecha y hora", selection: $date, displayedComponents: [.date, .hourAndMinute])
                }

                Section {
                    TextField("Nota (0 - 10)", text: $gradeText)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Calificación (opcional)")
                } footer: {
                    if !gradeIsValid {
                        Text("La nota debe estar entre 0 y 10.")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isNew ? "Nuevo componente" : "Editar componente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .disabled(trimmedName.isEmpty || !gradeIsValid)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        var result = original
        result.name = trimmedName
        result.date = date
        result.grade = trimmedGrade.isEmpty ? nil : grade
        onSave(result)
        dismiss()
    }
}
