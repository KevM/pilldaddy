import SwiftUI
import SwiftData

/// Host for the Meds tab: Regime ⇄ All Meds toggle and an add menu.
struct MedsView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case regime = "Regime"
        case allMeds = "All Meds"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .regime
    @State private var showingAddMed = false
    @State private var showingAddBatch = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()
                ZStack {
                    RegimeView()
                        .opacity(mode == .regime ? 1.0 : 0.0)
                        .disabled(mode != .regime)
                        .allowsHitTesting(mode == .regime)
                        .accessibilityHidden(mode != .regime)
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
                        Button("Add batch") { showingAddBatch = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddMed) { MedicationEditor(mode: .add) }
            .sheet(isPresented: $showingAddBatch) { BatchEditor(batch: nil) }
        }
    }
}

#if DEBUG
#Preview {
    MedsView()
        .modelContainer(PreviewSupport.seededContainer())
}
#endif
