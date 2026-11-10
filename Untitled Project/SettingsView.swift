import SwiftUI
import EventKit
import UIKit

// MARK: - APARIENCIA (claro / oscuro / sistema)
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appAppearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Sistema"
        case .light: return "Claro"
        case .dark: return "Oscuro"
        }
    }

    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified   // sigue al dispositivo
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// Aplica el modo a todas las ventanas de la app (hojas y popovers incluidos).
    /// Es más fiable que `.preferredColorScheme`, que no siempre vuelve a "Sistema".
    @MainActor
    static func apply(_ appearance: AppAppearance) {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = appearance.userInterfaceStyle
            }
        }
    }
}

struct SettingsView: View {
    let viewModel: PlannerViewModel
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    private let calendarSync = CalendarSyncManager.shared

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
    
    var body: some View {
        List {
            // SECCIÓN 0: APARIENCIA
            Section {
                Picker("Apariencia", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Apariencia")
            } footer: {
                Text("«Sistema» sigue el modo claro u oscuro de tu dispositivo.")
            }

            // SECCIÓN 1: SINCRONIZACIÓN DE CALENDARIO NATIVO
            Section(
                header: Text("Sincronización con Calendario"),
                footer: Text("Selecciona el calendario de tu dispositivo donde se crearán, editarán y eliminarán automáticamente tus exámenes.")
            ) {
                switch calendarSync.authorizationState {
                case .fullAccess:
                    HStack {
                        Label("Estado", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Text("Conectado")
                            .foregroundStyle(.secondary)
                    }
                    
                    Picker("Calendario Destino", selection: Binding(
                        get: { calendarSync.selectedCalendarID },
                        set: { calendarSync.select($0) }
                    )) {
                        ForEach(calendarSync.availableCalendars, id: \.calendarIdentifier) { cal in
                            Text(cal.title).tag(cal.calendarIdentifier)
                        }
                    }
                    
                    Button("Recargar Calendarios") {
                        calendarSync.loadCalendars()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.blue)
                    
                case .denied, .restricted:
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Acceso Denegado", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .bold()
                        Text("iOS ha bloqueado el acceso al calendario para esta app. Para activarlo, abre los Ajustes de iOS.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Button("Abrir Ajustes de iOS") {
                            calendarSync.openSystemSettings()
                        }
                        .font(.subheadline)
                        .bold()
                        .foregroundStyle(.blue)
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                    
                default:
                    Button(action: { Task { await calendarSync.requestAccess() } }) {
                        HStack {
                            Image(systemName: "calendar.badge.plus")
                                .font(.headline)
                                .foregroundStyle(.blue)
                            
                            VStack(alignment: .leading) {
                                Text("Conectar Calendario")
                                    .bold()
                                    .foregroundStyle(.blue)
                                Text("Permitir acceso a los calendarios de iOS")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            
            // SECCIÓN 2: GESTIÓN ACADÉMICA
            Section(header: Text("Gestión Académica")) {
                NavigationLink(destination: ScheduleConfigView(viewModel: viewModel)) {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.title3)
                            .foregroundStyle(.blue)
                            .frame(width: 32, height: 32)
                            .background(Color.blue.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Configurar Horario Semanal")
                                .font(.headline)
                            Text("Asigna materias y aulas de Lunes a Viernes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            
            // SECCIÓN 3: INFORMACIÓN
            Section(header: Text("Información de la App")) {
                LabeledContent("Aplicación", value: "Planner Academic")
                LabeledContent("Versión", value: appVersion)
                LabeledContent("Framework", value: "SwiftUI & EventKit")
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.defaultMinListHeaderHeight, 0)
        .navigationTitle("Ajustes")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            calendarSync.refreshAuthorization()
        }
    }
}
