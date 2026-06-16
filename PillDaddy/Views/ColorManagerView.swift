import SwiftUI
import SwiftData

struct ColorManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PillColor.name) private var colors: [PillColor]
    
    @State private var showingAddSheet = false
    @State private var editingColor: PillColor? = nil
    
    @State private var colorName = ""
    @State private var selectedColor = Color.blue
    
    // Preset attractive colors for easy selection
    private let presets = [
        "#EF4444", // Red
        "#F59E0B", // Amber/Yellow
        "#10B981", // Green
        "#14B8A6", // Teal
        "#3B82F6", // Blue
        "#8B5CF6", // Purple
        "#EC4899", // Pink
        "#F97316"  // Orange
    ]
    
    var body: some View {
        ZStack {
            Theme.backgroundGradient
                .ignoresSafeArea()
            
            VStack {
                if colors.isEmpty {
                    ContentUnavailableView(
                        "No Colors Configured",
                        systemImage: "paintpalette.fill",
                        description: Text("Add colors to categorize your pills in the regime.")
                    )
                } else {
                    List {
                        ForEach(colors) { color in
                            HStack(spacing: 16) {
                                Circle()
                                    .fill(Color(hex: color.colorHex))
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                                    .shadow(color: Color(hex: color.colorHex).opacity(0.4), radius: 6)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(color.name)
                                        .font(.headline)
                                        .foregroundColor(Theme.textPrimary)
                                    Text("\(color.pills?.count ?? 0) pills assigned")
                                        .font(.caption)
                                        .foregroundColor(Theme.textSecondary)
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    colorName = color.name
                                    selectedColor = Color(hex: color.colorHex)
                                    editingColor = color
                                }) {
                                    Image(systemName: "pencil")
                                        .foregroundColor(Color(hex: "#38BDF8"))
                                        .padding(8)
                                        .background(Circle().fill(Color.white.opacity(0.06)))
                                }
                                .buttonStyle(.plain)
                            }
                            .listRowBackground(Theme.cardBackground)
                            .listRowSeparatorTint(Theme.cardBorder)
                        }
                        .onDelete(perform: deleteColors)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Pill Colors")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        colorName = ""
                        selectedColor = Color(hex: presets[0])
                        showingAddSheet = true
                    }) {
                        Image(systemName: "plus")
                            .font(.bold(.body)())
                            .foregroundColor(Color(hex: "#38BDF8"))
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                colorFormSheet(title: "Create Color Group", actionText: "Create") {
                    let hex = selectedColor.toHex()
                    let newColor = PillColor(name: colorName, colorHex: hex)
                    modelContext.insert(newColor)
                    showingAddSheet = false
                }
            }
            .sheet(item: $editingColor) { color in
                colorFormSheet(title: "Edit Color Group", actionText: "Update") {
                    color.name = colorName
                    color.colorHex = selectedColor.toHex()
                    editingColor = nil
                }
            }
        }
    }
    
    private func deleteColors(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(colors[index])
            }
        }
    }
    
    private func colorFormSheet(title: String, actionText: String, onSave: @escaping () -> Void) -> some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("COLOR NAME")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.textSecondary)
                            .padding(.leading, 8)
                        
                        TextField("e.g. Morning Red", text: $colorName)
                            .padding()
                            .background(Theme.cardBackground)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Theme.cardBorder, lineWidth: 1)
                            )
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("PRESETS")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.textSecondary)
                            .padding(.leading, 8)
                        
                        HStack(spacing: 12) {
                            ForEach(presets, id: \.self) { hex in
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 34, height: 34)
                                    .overlay(
                                        Circle()
                                            .stroke(selectedColor.toHex() == hex ? Color.white : Color.clear, lineWidth: 2)
                                    )
                                    .onTapGesture {
                                        withAnimation {
                                            selectedColor = Color(hex: hex)
                                        }
                                    }
                            }
                        }
                        
                        Divider()
                            .background(Theme.cardBorder)
                            .padding(.vertical, 8)
                        
                        ColorPicker("Custom Tone", selection: $selectedColor, supportsOpacity: false)
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                    }
                    
                    Spacer()
                    
                    Button(action: onSave) {
                        Text(actionText)
                            .frame(maxWidth: .infinity)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding()
                            .background(
                                colorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? LinearGradient(colors: [Color.gray.opacity(0.3)], startPoint: .leading, endPoint: .trailing)
                                : Theme.accentGradient
                            )
                            .cornerRadius(12)
                    }
                    .disabled(colorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        showingAddSheet = false
                        editingColor = nil
                    }
                    .foregroundColor(Color(hex: "#38BDF8"))
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
