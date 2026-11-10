import SwiftUI
import Observation
import UserNotifications

// MARK: - GESTOR DEL TEMPORIZADOR (3 h diarias, reinicio a las 07:00)
// En lugar de un Timer que resta 1 s y guarda en UserDefaults cada segundo,
// se guarda UNA fecha de fin (`endDate`). El tiempo restante siempre se deriva
// de ella, así que no hay deriva, no hay escrituras continuas y sobrevive a
// cerrar la app sin lógica de recuperación. La interfaz se refresca con
// TimelineView solo mientras el desplegable está abierto.
@MainActor
@Observable
final class StudyTimerManager {
    static let totalDailySeconds: TimeInterval = 3 * 3600

    /// Tiempo restante mientras está en pausa
    private(set) var pausedRemaining: TimeInterval
    /// Momento en que llega a 0. Solo existe mientras corre.
    private(set) var endDate: Date?

    var isRunning: Bool { endDate != nil }

    @ObservationIgnored private var cycleStart: Date
    @ObservationIgnored private var wakeTask: Task<Void, Never>?

    private enum Keys {
        static let remaining = "StudyTimer_SecondsRemaining"
        static let endDate = "StudyTimer_EndDate"
        static let cycle = "StudyTimer_LastCycle7AM"
        static let notification = "study-timer-finished"
    }

    init() {
        let defaults = UserDefaults.standard
        pausedRemaining = defaults.object(forKey: Keys.remaining) as? Double ?? Self.totalDailySeconds
        let end = defaults.double(forKey: Keys.endDate)
        endDate = end > 0 ? Date(timeIntervalSince1970: end) : nil
        cycleStart = Date(timeIntervalSince1970: defaults.double(forKey: Keys.cycle))
        refresh()
    }

    // MARK: Lectura
    func remaining(at date: Date = .now) -> TimeInterval {
        if let endDate { return max(0, endDate.timeIntervalSince(date)) }
        return pausedRemaining
    }

    // MARK: Controles
    func toggle() {
        refresh()
        isRunning ? pause() : start()
    }

    func start() {
        guard !isRunning, pausedRemaining > 0 else { return }
        endDate = Date().addingTimeInterval(pausedRemaining)
        persist()
        scheduleWake()
        scheduleFinishNotification()
    }

    func pause() {
        guard isRunning else { return }
        pausedRemaining = remaining()
        endDate = nil
        persist()
        scheduleWake()
        cancelFinishNotification()
    }

    func reset() {
        endDate = nil
        pausedRemaining = Self.totalDailySeconds
        persist()
        scheduleWake()
        cancelFinishNotification()
    }

    /// Aplica el reinicio de las 07:00 y detecta si el tiempo ya terminó.
    /// Llamar al volver a primer plano.
    func refresh(now: Date = .now) {
        let currentCycle = Self.cycleStart(for: now)
        if currentCycle > cycleStart {
            cycleStart = currentCycle
            endDate = nil
            pausedRemaining = Self.totalDailySeconds
            persist()
            cancelFinishNotification()
        } else if let end = endDate, end <= now {
            endDate = nil
            pausedRemaining = 0
            persist()
        }
        scheduleWake(now: now)
    }

    // MARK: Internos
    /// Último hito de las 07:00 (hoy, o ayer si aún no son las 07:00)
    private static func cycleStart(for date: Date) -> Date {
        let calendar = Calendar.current
        guard let today7AM = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: date) else { return date }
        return date < today7AM ? (calendar.date(byAdding: .day, value: -1, to: today7AM) ?? today7AM) : today7AM
    }

    /// Una sola tarea dormida hasta el próximo evento (fin del timer o las 07:00)
    private func scheduleWake(now: Date = .now) {
        wakeTask?.cancel()
        var target = Calendar.current.date(byAdding: .day, value: 1, to: cycleStart) ?? now.addingTimeInterval(86_400)
        if let endDate, endDate < target { target = endDate }
        let delay = max(0.1, target.timeIntervalSince(now) + 0.1)

        wakeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(pausedRemaining, forKey: Keys.remaining)
        defaults.set(endDate?.timeIntervalSince1970 ?? 0, forKey: Keys.endDate)
        defaults.set(cycleStart.timeIntervalSince1970, forKey: Keys.cycle)
    }

    // MARK: Aviso al terminar (la app puede estar cerrada)
    private func scheduleFinishNotification() {
        let center = UNUserNotificationCenter.current()
        Task {
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true,
                  let end = endDate else { return }

            let content = UNMutableNotificationContent()
            content.title = "Tiempo de estudio completado"
            content.body = "Has cumplido tus 3 horas de hoy."
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: Keys.notification, content: content, trigger: trigger))
        }
    }

    private func cancelFinishNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Keys.notification])
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}

// MARK: - CONTENIDO DEL DESPLEGABLE DEL TIMER (estilo app Reloj de iOS)
struct StudyTimerPopover: View {
    let timerManager: StudyTimerManager

    var body: some View {
        // Solo se actualiza cada segundo mientras el popover está visible
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(at: context.date)
        }
        .padding(24)
        .frame(width: 310)
    }

    private func content(at date: Date) -> some View {
        let remaining = timerManager.remaining(at: date)
        let progress = remaining / StudyTimerManager.totalDailySeconds
        let isFinished = remaining <= 0

        return VStack(spacing: 24) {
            // ANILLO + TIEMPO
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.25), lineWidth: 8)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1.0), value: remaining)

                VStack(spacing: 6) {
                    Text(StudyTimerManager.format(remaining))
                        .font(.system(size: 46, weight: .thin))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)

                    statusLabel(isFinished: isFinished)
                }
                .padding(.horizontal, 24)
            }
            .frame(width: 230, height: 230)

            // BOTONES CIRCULARES
            HStack {
                TimerCircleButton(title: "Reiniciar", color: .gray, textColor: .primary) {
                    timerManager.reset()
                }

                Spacer()

                if timerManager.isRunning {
                    TimerCircleButton(title: "Pausar", color: .orange, textColor: .orange) {
                        timerManager.toggle()
                    }
                } else {
                    TimerCircleButton(
                        title: progress < 1 && !isFinished ? "Reanudar" : "Iniciar",
                        color: isFinished ? .gray : .green,
                        textColor: isFinished ? .secondary : .green
                    ) {
                        timerManager.toggle()
                    }
                    .disabled(isFinished)
                }
            }

            Text("3 horas diarias • Reinicio a las 07:00")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func statusLabel(isFinished: Bool) -> some View {
        if isFinished {
            Text("Completado")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if let end = timerManager.endDate {
            Label {
                Text(end, format: .dateTime.hour().minute())
            } icon: {
                Image(systemName: "bell.fill")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        } else {
            Text("En pausa")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - BOTÓN CIRCULAR COMO EN LA APP RELOJ
private struct TimerCircleButton: View {
    let title: String
    let color: Color
    let textColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.22))
                    .padding(4)
                Circle()
                    .stroke(color.opacity(0.22), lineWidth: 1.5)
                Text(title)
                    .font(.callout)
                    .foregroundStyle(textColor)
            }
            .frame(width: 84, height: 84)
        }
        .buttonStyle(.plain)
    }
}
