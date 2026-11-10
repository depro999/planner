import SwiftUI
import UIKit

// MARK: - PANTALLA DE CALENDARIO (UICalendarView nativo)
struct CalendarView: View {
    let viewModel: PlannerViewModel
    @State private var selectedDate = Date()

    private let calendar = Calendar.current

    var body: some View {
        List {
            Section {
                ExamCalendarView(selectedDate: $selectedDate, examColorsByDay: examColorsByDay)
            }

            Section {
                if selectedDayExams.isEmpty {
                    ContentUnavailableView(
                        "Sin exámenes",
                        systemImage: "calendar.badge.checkmark",
                        description: Text("No hay exámenes pendientes para este día.")
                    )
                } else {
                    ForEach(selectedDayExams) { item in
                        HStack(spacing: 12) {
                            Capsule()
                                .fill(item.color)
                                .frame(width: 4, height: 40)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name)
                                    .font(.headline)
                                Text(item.subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(item.date, format: .dateTime.hour().minute())
                                    .font(.caption)
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
            } header: {
                Text(selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .textCase(nil)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Calendario")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Hoy") {
                    selectedDate = Date()
                }
            }
        }
    }

    // MARK: Datos
    private var pendingExams: [UpcomingExamItem] {
        viewModel.subjects.flatMap(\.scheduledExams)
    }

    /// Colores distintos (uno por asignatura) de los exámenes pendientes de cada día
    private var examColorsByDay: [Date: [Color]] {
        var result: [Date: [Color]] = [:]
        for item in pendingExams {
            let day = calendar.startOfDay(for: item.date)
            if !(result[day]?.contains(item.color) ?? false) {
                result[day, default: []].append(item.color)
            }
        }
        return result
    }

    private var selectedDayExams: [UpcomingExamItem] {
        pendingExams
            .filter { calendar.isDate($0.date, inSameDayAs: selectedDate) }
            .sorted { $0.date < $1.date }
    }
}

// MARK: - CLAVE DE DÍA (año-mes-día, sin horas ni zonas horarias de por medio)
struct DayKey: Hashable {
    let year: Int
    let month: Int
    let day: Int

    init(_ components: DateComponents) {
        year = components.year ?? 0
        month = components.month ?? 0
        day = components.day ?? 0
    }

    init(_ date: Date) {
        self.init(Calendar.current.dateComponents([.year, .month, .day], from: date))
    }

    var components: DateComponents {
        DateComponents(year: year, month: month, day: day)
    }
}

// MARK: - BARRA DE COLOR (vista con tamaño propio, sin constraints)
final class ExamBarView: UIView {
    private static let verticalOffset: CGFloat = 4
    private let colors: [UIColor]
    private var segmentLayers: [CALayer] = []

    init(colors: [UIColor]) {
        self.colors = colors
        super.init(frame: CGRect(x: 0, y: 0, width: 22, height: 4))
        layer.cornerRadius = 2
        layer.masksToBounds = true
        // Acerca la barra al número del día (ajusta este valor a tu gusto)
        transform = CGAffineTransform(translationX: 0, y: -Self.verticalOffset)
        for color in colors {
            let segment = CALayer()
            segment.backgroundColor = color.cgColor
            layer.addSublayer(segment)
            segmentLayers.append(segment)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no implementado") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 22, height: 4)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !segmentLayers.isEmpty else { return }
        let width = bounds.width / CGFloat(segmentLayers.count)
        for (i, segment) in segmentLayers.enumerated() {
            segment.frame = CGRect(x: CGFloat(i) * width, y: 0, width: width, height: bounds.height)
        }
    }
}

// MARK: - ENVOLTORIO DE UICalendarView
struct ExamCalendarView: UIViewRepresentable {
    @Binding var selectedDate: Date
    let examColorsByDay: [Date: [Color]]

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedDate: $selectedDate)
    }

    func makeUIView(context: Context) -> UICalendarView {
        let view = UICalendarView()
        view.calendar = .current
        view.locale = .current
        view.delegate = context.coordinator

        let selection = UICalendarSelectionSingleDate(delegate: context.coordinator)
        selection.setSelected(DayKey(selectedDate).components, animated: false)
        view.selectionBehavior = selection

        context.coordinator.selection = selection
        context.coordinator.decorations = Self.uiColors(from: examColorsByDay)
        return view
    }

    func updateUIView(_ view: UICalendarView, context: Context) {
        let coordinator = context.coordinator
        coordinator.selectedDate = $selectedDate

        // Barras de exámenes: recarga los días que han cambiado
        let newDecorations = Self.uiColors(from: examColorsByDay)
        if newDecorations != coordinator.decorations {
            let changedDays = Set(coordinator.decorations.keys).union(newDecorations.keys)
            coordinator.decorations = newDecorations
            view.reloadDecorations(forDateComponents: changedDays.map { $0.components }, animated: false)
        }

        // Selección cambiada desde fuera (botón "Hoy")
        let target = DayKey(selectedDate)
        if let current = coordinator.selection?.selectedDate, DayKey(current) == target { return }
        coordinator.selection?.setSelected(target.components, animated: true)
        view.setVisibleDateComponents(target.components, animated: true)
    }

    // Permite que SwiftUI calcule la altura real del calendario nativo
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UICalendarView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        let fitted = uiView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingExpandedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return CGSize(width: width, height: fitted.height)
    }

    private static func uiColors(from colors: [Date: [Color]]) -> [DayKey: [UIColor]] {
        var result: [DayKey: [UIColor]] = [:]
        for (date, dayColors) in colors {
            result[DayKey(date)] = dayColors.map { UIColor($0) }
        }
        return result
    }

    // MARK: Coordinator
    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        var selectedDate: Binding<Date>
        var selection: UICalendarSelectionSingleDate?
        var decorations: [DayKey: [UIColor]] = [:]

        init(selectedDate: Binding<Date>) {
            self.selectedDate = selectedDate
        }

        /// Barra de color bajo el número (como en la app Calendario).
        /// Con varios exámenes, la barra se reparte en tramos, uno por color.
        func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? {
            guard let colors = decorations[DayKey(dateComponents)], !colors.isEmpty else { return nil }
            return .customView {
                ExamBarView(colors: colors)
            }
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
            guard let components = dateComponents,
                  let date = Calendar.current.date(from: components) else { return }
            selectedDate.wrappedValue = date
        }
    }
}
