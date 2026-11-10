import EventKit
import Observation
import UIKit
import os

@MainActor
@Observable
final class CalendarSyncManager {
    static let shared = CalendarSyncManager()

    private(set) var authorizationState: EKAuthorizationStatus = .notDetermined
    private(set) var availableCalendars: [EKCalendar] = []
    private(set) var selectedCalendarID: String

    var hasAccess: Bool { authorizationState == .fullAccess }

    private let eventStore = EKEventStore()
    private let selectedKey = "SelectedCalendarID"
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Planner", category: "Calendar")

    private init() {
        selectedCalendarID = UserDefaults.standard.string(forKey: "SelectedCalendarID") ?? ""

        // Si el usuario cambia algo en la app Calendario, nos enteramos
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: eventStore, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.loadCalendars() }
        }
        refreshAuthorization()
    }

    // MARK: Permisos
    func refreshAuthorization() {
        authorizationState = EKEventStore.authorizationStatus(for: .event)
        if hasAccess { loadCalendars() }
    }

    func requestAccess() async {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .denied, .restricted:
            openSystemSettings()
            return
        default:
            break
        }
        _ = try? await eventStore.requestFullAccessToEvents()
        refreshAuthorization()
    }

    func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: Calendarios
    func loadCalendars() {
        guard hasAccess else { return }
        // Solo calendarios donde se puede escribir (excluye festivos, suscripciones…)
        let calendars = eventStore.calendars(for: .event).filter(\.allowsContentModifications)
        availableCalendars = calendars

        if !calendars.contains(where: { $0.calendarIdentifier == selectedCalendarID }) {
            let fallback = eventStore.defaultCalendarForNewEvents ?? calendars.first
            select(fallback?.calendarIdentifier ?? "")
        }
    }

    func select(_ calendarID: String) {
        selectedCalendarID = calendarID
        UserDefaults.standard.set(calendarID, forKey: selectedKey)
    }

    private var targetCalendar: EKCalendar? {
        eventStore.calendar(withIdentifier: selectedCalendarID) ?? eventStore.defaultCalendarForNewEvents
    }

    // MARK: Operaciones de sincronización
    func createEvent(title: String, date: Date, notes: String) -> String? {
        guard hasAccess, let calendar = targetCalendar else { return nil }

        let event = EKEvent(eventStore: eventStore)
        fill(event, title: title, date: date, notes: notes)
        event.calendar = calendar

        do {
            try eventStore.save(event, span: .thisEvent)
            return event.eventIdentifier
        } catch {
            log.error("No se pudo crear el evento: \(error.localizedDescription)")
            return nil
        }
    }

    /// Actualiza el evento existente o, si ya no existe, crea uno nuevo. Devuelve su identificador.
    func upsertEvent(identifier: String?, title: String, date: Date, notes: String) -> String? {
        guard hasAccess else { return identifier }

        if let identifier, !identifier.isEmpty, let event = eventStore.event(withIdentifier: identifier) {
            fill(event, title: title, date: date, notes: notes)
            do {
                try eventStore.save(event, span: .thisEvent)
            } catch {
                log.error("No se pudo actualizar el evento: \(error.localizedDescription)")
            }
            return identifier
        }
        return createEvent(title: title, date: date, notes: notes)
    }

    func deleteEvent(identifier: String?) {
        guard hasAccess, let identifier, !identifier.isEmpty,
              let event = eventStore.event(withIdentifier: identifier) else { return }
        do {
            try eventStore.remove(event, span: .thisEvent)
        } catch {
            log.error("No se pudo borrar el evento: \(error.localizedDescription)")
        }
    }

    private func fill(_ event: EKEvent, title: String, date: Date, notes: String) {
        event.title = title
        event.startDate = date
        event.endDate = date.addingTimeInterval(3600)
        event.notes = notes
    }
}
