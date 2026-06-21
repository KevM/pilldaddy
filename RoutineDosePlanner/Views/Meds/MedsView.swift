import SwiftUI
import SwiftData

/// Host for the Meds tab: Routines ⇄ All Meds toggle and an add menu.
struct MedsView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case routines = "Routines"
        case allMeds = "All Meds"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .routines
    @State private var showingAddMed = false
    @State private var showingAddRoutine = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()
                ZStack {
                    RoutinesView()
                        .opacity(mode == .routines ? 1.0 : 0.0)
                        .disabled(mode != .routines)
                        .allowsHitTesting(mode == .routines)
                        .accessibilityHidden(mode != .routines)
                    AllMedsView()
                        .opacity(mode == .allMeds ? 1.0 : 0.0)
                        .disabled(mode != .allMeds)
                        .allowsHitTesting(mode == .allMeds)
                        .accessibilityHidden(mode != .allMeds)
                }
            }
            .navigationTitle("Meds")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Add medication") { showingAddMed = true }
                        Button("Add routine") { showingAddRoutine = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddMed) { MedicationEditor(mode: .add) }
            .sheet(isPresented: $showingAddRoutine) { RoutineEditor(routine: nil) }
        }
    }
}

#if DEBUG
#Preview {
    MedsView()
        .modelContainer(PreviewSupport.seededContainer())
}
#endif
