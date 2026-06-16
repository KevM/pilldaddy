import SwiftUI
import SwiftData

struct PillManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Pill.name) private var pills: [Pill]
    
    @State private var editingPill: Pill? = nil
    @State private var showingAddSheet = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient
                    .ignoresSafeArea()
                
                VStack {
                    if pills.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "cabinet.fill")
                                .font(.system(size: 64))
                                .foregroundStyle(Theme.accentGradient)
                                .opacity(0.8)
                            
                            Text("Medication Cabinet is Empty")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text("Add your pills and organize them under custom color groups to build your regime.")
                                .font(.subheadline)
                                .foregroundColor(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                            
                            Button(action: {
                                showingAddSheet = true
                            }) {
                                Text("Add Your First Pill")
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                                    .background(Theme.accentGradient)
                                    .cornerRadius(12)
                            }
                            .padding(.top, 10)
                        }
                        .padding(.top, 80)
                        .glassmorphicCard()
                        .padding()
                        
                        Spacer()
                    } else {
                        List {
                            Section {
                                ForEach(pills) { pill in
                                    HStack(spacing: 16) {
                                        PillImageView(imageUrlString: pill.imageUrlString, defaultColorHex: pill.pillColor?.colorHex, shapeName: pill.shapeName, size: 40)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(pill.name)
                                                .font(.headline)
                                                .foregroundColor(Theme.textPrimary)
                                            
                                            HStack(spacing: 8) {
                                                Text(pill.dosage)
                                                    .font(.caption)
                                                    .foregroundColor(Theme.textSecondary)
                                                
                                                if let colorName = pill.pillColor?.name {
                                                    Text("•")
                                                        .font(.caption)
                                                        .foregroundColor(Theme.textSecondary)
                                                    Text(colorName)
                                                        .font(.caption)
                                                        .foregroundColor(Theme.textSecondary)
                                                }
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        HStack(spacing: 12) {
                                            Text(pill.scheduleTime.formatted(date: .omitted, time: .shortened))
                                                .font(.subheadline)
                                                .foregroundColor(Theme.textSecondary)
                                            
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundColor(Theme.textSecondary)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        editingPill = pill
                                    }
                                    .listRowBackground(Theme.cardBackground)
                                    .listRowSeparatorTint(Theme.cardBorder)
                                }
                                .onDelete(perform: deletePills)
                            } header: {
                                Text("ACTIVE MEDICATIONS")
                                    .foregroundColor(Theme.textSecondary)
                            }
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
                .navigationTitle("Cabinet")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink(destination: ColorManagerView()) {
                            HStack(spacing: 4) {
                                Image(systemName: "paintpalette.fill")
                                Text("Colors")
                            }
                            .foregroundColor(Color(hex: "#38BDF8"))
                        }
                    }
                    
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: {
                            showingAddSheet = true
                        }) {
                            Image(systemName: "plus")
                                .font(.bold(.body)())
                                .foregroundColor(Color(hex: "#38BDF8"))
                        }
                    }
                }
                .sheet(isPresented: $showingAddSheet) {
                    PillEditView()
                }
                .sheet(item: $editingPill) { pill in
                    PillEditView(pill: pill)
                }
            }
        }
    }
    
    private func deletePills(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(pills[index])
            }
            try? modelContext.save()
        }
    }
}
