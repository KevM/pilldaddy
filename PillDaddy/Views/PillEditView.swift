import SwiftUI
import SwiftData

struct PillEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    var pill: Pill?
    
    @Query(sort: \PillColor.name) private var colors: [PillColor]
    
    @State private var name = ""
    @State private var dosage = ""
    @State private var scheduleTime = Date()
    @State private var selectedColor: PillColor? = nil
    
    // Dosage change note tracking
    @State private var showingChangeNoteSheet = false
    @State private var dosageChangeReason = ""
    
    // API State
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var searchResults: [DailyMedSearchResult] = []
    @State private var isSearching = false
    @State private var isFetchingDetails = false
    
    // Loaded Metadata
    @State private var ndc: String? = nil
    @State private var splSetId: String? = nil
    @State private var imageUrlString: String? = nil
    @State private var imprint: String? = nil
    @State private var shapeName: String? = nil
    @State private var colorDescription: String? = nil
    
    // Custom Appearance Shape selection
    @State private var shapeSelection: PillShape = .round
    
    // List of available image URLs returned by DailyMed API
    @State private var availableImageUrls: [String] = []
    
    init(pill: Pill? = nil) {
        self.pill = pill
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient
                    .ignoresSafeArea()
                
                Form {
                    // Live Premium Pill Preview Card
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                PillImageView(
                                    imageUrlString: imageUrlString,
                                    defaultColorHex: selectedColor?.colorHex,
                                    shapeName: shapeSelection.rawValue,
                                    size: 96
                                )
                                .shadow(color: Color(hex: selectedColor?.colorHex ?? "#38BDF8").opacity(0.3), radius: 10)
                                
                                Text(name.isEmpty ? "New Medication" : name)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                                
                                if !dosage.isEmpty {
                                    Text(dosage)
                                        .font(.subheadline)
                                        .foregroundColor(Theme.textSecondary)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                    .listRowBackground(Color.clear)
                    
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("PILL NAME")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(Theme.textSecondary)
                            HStack {
                                TextField("e.g. Lipitor", text: $name)
                                    .foregroundColor(.white)
                                    .textFieldStyle(.plain)
                                
                                if isSearching {
                                    ProgressView()
                                        .tint(Color(hex: "#38BDF8"))
                                } else if !name.isEmpty {
                                    Button(action: {
                                        name = ""
                                        searchResults = []
                                        imageUrlString = nil
                                        ndc = nil
                                        imprint = nil
                                        shapeName = nil
                                        colorDescription = nil
                                        splSetId = nil
                                        shapeSelection = .round
                                        availableImageUrls = []
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(Theme.textSecondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        
                        // Suggestion Dropdown List
                        if !searchResults.isEmpty {
                            ForEach(searchResults) { result in
                                Button(action: {
                                    selectMedication(result)
                                }) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(MedicationAPIService.shared.cleanTitle(result.title))
                                                .foregroundColor(.white)
                                                .font(.body)
                                            Text("SetID: \(result.setid.prefix(8))...")
                                                .font(.caption2)
                                                .foregroundColor(Theme.textSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.down.right.circle.fill")
                                            .foregroundColor(Color(hex: "#38BDF8"))
                                    }
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("DOSAGE")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(Theme.textSecondary)
                            TextField("e.g. 10mg, 1 tablet", text: $dosage)
                                .foregroundColor(.white)
                                .textFieldStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("Medication Details")
                            .foregroundColor(Theme.textSecondary)
                    }
                    .listRowBackground(Theme.cardBackground)
                    
                    // Image Gallery Selection Carousel
                    if !availableImageUrls.isEmpty {
                        Section {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("SELECT PILL IMAGE")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(Theme.textSecondary)
                                    .padding(.leading, 4)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(availableImageUrls, id: \.self) { url in
                                            Button(action: {
                                                withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                                                    imageUrlString = url
                                                }
                                            }) {
                                                ZStack {
                                                    AsyncImage(url: URL(string: url)) { phase in
                                                        switch phase {
                                                        case .success(let image):
                                                            image
                                                                .resizable()
                                                                .aspectRatio(contentMode: .fit)
                                                        case .failure(_):
                                                            Image(systemName: "photo")
                                                                .foregroundColor(Theme.textSecondary)
                                                        case .empty:
                                                            ProgressView()
                                                                .tint(.white.opacity(0.3))
                                                        @unknown default:
                                                            EmptyView()
                                                        }
                                                    }
                                                    .frame(width: 80, height: 80)
                                                    .background(Color.white.opacity(0.03))
                                                    .cornerRadius(12)
                                                    
                                                    if imageUrlString == url {
                                                        RoundedRectangle(cornerRadius: 12)
                                                            .stroke(Color(hex: "#38BDF8"), lineWidth: 2.5)
                                                    } else {
                                                        RoundedRectangle(cornerRadius: 12)
                                                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                                    }
                                                }
                                                .frame(width: 80, height: 80)
                                                .shadow(color: imageUrlString == url ? Color(hex: "#38BDF8").opacity(0.25) : Color.clear, radius: 4)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                            .padding(.vertical, 4)
                        } header: {
                            Text("Medication Images")
                                .foregroundColor(Theme.textSecondary)
                        }
                        .listRowBackground(Theme.cardBackground)
                    }
                    
                    if isFetchingDetails {
                        Section {
                            HStack(spacing: 12) {
                                ProgressView()
                                    .tint(Color(hex: "#38BDF8"))
                                Text("Fetching medication details...")
                                    .foregroundColor(Theme.textSecondary)
                                    .font(.footnote)
                            }
                        }
                        .listRowBackground(Theme.cardBackground)
                    } else if ndc != nil || imprint != nil || shapeName != nil || colorDescription != nil {
                        Section {
                            if let ndc = ndc {
                                HStack {
                                    Text("NDC Code")
                                        .foregroundColor(Theme.textSecondary)
                                    Spacer()
                                    Text(ndc)
                                        .foregroundColor(.white)
                                        .font(.subheadline)
                                }
                            }
                            
                            if let imprint = imprint {
                                HStack {
                                    Text("Imprint")
                                        .foregroundColor(Theme.textSecondary)
                                    Spacer()
                                    Text(imprint)
                                        .foregroundColor(.white)
                                        .font(.subheadline)
                                }
                            }
                            
                            if let shape = shapeName {
                                HStack {
                                    Text("Official Shape")
                                        .foregroundColor(Theme.textSecondary)
                                    Spacer()
                                    Text(shape.capitalized)
                                        .foregroundColor(.white)
                                        .font(.subheadline)
                                }
                            }
                            
                            if let colorDesc = colorDescription {
                                HStack(alignment: .top) {
                                    Text("Color Description")
                                        .foregroundColor(Theme.textSecondary)
                                    Spacer()
                                    Text(colorDesc)
                                        .foregroundColor(.white)
                                        .font(.caption)
                                        .multilineTextAlignment(.trailing)
                                        .frame(maxWidth: 200)
                                }
                            }
                        } header: {
                            Text("Official Visual Properties")
                                .foregroundColor(Theme.textSecondary)
                        }
                        .listRowBackground(Theme.cardBackground)
                    }
                    
                    Section {
                        DatePicker("Reminder Time", selection: $scheduleTime, displayedComponents: .hourAndMinute)
                            .foregroundColor(.white)
                        
                        Picker("Color Group", selection: $selectedColor) {
                            Text("No Group").tag(nil as PillColor?)
                            ForEach(colors) { color in
                                HStack {
                                    Image(systemName: "circle.fill")
                                        .foregroundColor(Color(hex: color.colorHex))
                                    Text(color.name)
                                        .foregroundColor(.white)
                                }
                                .tag(color as PillColor?)
                            }
                        }
                        .foregroundColor(.white)
                    } header: {
                        Text("Schedule & Category")
                            .foregroundColor(Theme.textSecondary)
                    }
                    .listRowBackground(Theme.cardBackground)
                    
                    // Custom Shape Customization Grid
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("CUSTOM PILL SHAPE")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(Theme.textSecondary)
                                .padding(.leading, 4)
                            
                            HStack(spacing: 8) {
                                ForEach(PillShape.allCases) { shape in
                                    Button(action: {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                                            shapeSelection = shape
                                        }
                                    }) {
                                        VStack(spacing: 6) {
                                            PillShapeView(
                                                shapeName: shape.rawValue,
                                                colorHex: selectedColor?.colorHex ?? "#94A3B8",
                                                size: 28
                                            )
                                            .scaleEffect(shapeSelection == shape ? 1.15 : 1.0)
                                            
                                            Text(shape.rawValue)
                                                .font(.system(size: 9, weight: shapeSelection == shape ? .bold : .regular))
                                                .foregroundColor(shapeSelection == shape ? .white : Theme.textSecondary)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(shapeSelection == shape ? Color.white.opacity(0.08) : Color.clear)
                                        .cornerRadius(10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(shapeSelection == shape ? Color(hex: "#38BDF8").opacity(0.4) : Color.clear, lineWidth: 1.5)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("Pill Appearance Customization")
                            .foregroundColor(Theme.textSecondary)
                    }
                    .listRowBackground(Theme.cardBackground)
                    
                    Section {
                        Button(action: validateAndSave) {
                            Text(pill == nil ? "Create Pill" : "Save Changes")
                                .frame(maxWidth: .infinity)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding()
                                .background(
                                    (name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || dosage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                    ? LinearGradient(colors: [Color.gray.opacity(0.3)], startPoint: .leading, endPoint: .trailing)
                                    : Theme.accentGradient
                                )
                                .cornerRadius(12)
                        }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || dosage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .listRowBackground(Color.clear)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(pill == nil ? "Add Medication" : "Edit Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(Color(hex: "#38BDF8"))
                }
            }
            .onAppear {
                if let pill = pill {
                    name = pill.name
                    dosage = pill.dosage
                    scheduleTime = pill.scheduleTime
                    selectedColor = pill.pillColor
                    
                    ndc = pill.ndc
                    splSetId = pill.splSetId
                    imageUrlString = pill.imageUrlString
                    imprint = pill.imprint
                    shapeName = pill.shapeName
                    shapeSelection = PillShape(from: pill.shapeName)
                    colorDescription = pill.colorDescription
                    
                    // Fetch full list of DailyMed images on appear if splSetId is available
                    if let splSetId = pill.splSetId {
                        Task {
                            do {
                                let details = try await MedicationAPIService.shared.fetchDetails(for: splSetId)
                                await MainActor.run {
                                    self.availableImageUrls = details.imageUrls
                                }
                            } catch {
                                print("Failed to load details on appear: \(error)")
                            }
                        }
                    }
                } else if !colors.isEmpty {
                    selectedColor = colors.first
                }
            }
            .onChange(of: name) { oldValue, newValue in
                performSearch(query: newValue)
            }
            .sheet(isPresented: $showingChangeNoteSheet) {
                dosageChangeNoteSheet
            }
        }
    }
    
    private func performSearch(query: String) {
        searchTask?.cancel()
        
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        
        // If we are editing, don't trigger search if name matches original pill name
        if let pill = pill, trimmed == pill.name { return }
        
        // If name matches the metadata shape/color/details we already loaded, don't re-trigger search
        if let splSetId = splSetId, !splSetId.isEmpty {
            return
        }
        
        searchTask = Task {
            do {
                try await Task.sleep(nanoseconds: 500_000_000) // 500ms debounce
                guard !Task.isCancelled else { return }
                
                await MainActor.run { isSearching = true }
                let results = try await MedicationAPIService.shared.searchMedications(name: trimmed)
                
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.searchResults = results
                    self.isSearching = false
                }
            } catch {
                await MainActor.run { isSearching = false }
            }
        }
    }
    
    private func selectMedication(_ result: DailyMedSearchResult) {
        searchTask?.cancel()
        searchResults = []
        
        let cleanedTitle = MedicationAPIService.shared.cleanTitle(result.title)
        name = cleanedTitle
        splSetId = result.setid
        
        Task {
            await MainActor.run { isFetchingDetails = true }
            do {
                let details = try await MedicationAPIService.shared.fetchDetails(for: result.setid)
                await MainActor.run {
                    self.ndc = details.ndc
                    self.availableImageUrls = details.imageUrls
                    self.imageUrlString = details.imageUrls.first
                    self.imprint = details.imprint
                    self.shapeName = details.shapeText ?? details.shapeCode
                    self.shapeSelection = PillShape(from: details.shapeText ?? details.shapeCode)
                    self.colorDescription = details.colorText
                    
                    if let mappedColor = mapNCIColorToPillColor(details.colorCode, colors: colors) {
                        self.selectedColor = mappedColor
                    }
                    
                    self.isFetchingDetails = false
                }
            } catch {
                print("Failed to fetch medication details: \(error)")
                await MainActor.run { isFetchingDetails = false }
            }
        }
    }
    
    private func mapNCIColorToPillColor(_ conceptCode: String?, colors: [PillColor]) -> PillColor? {
        guard let code = conceptCode else { return nil }
        
        let colorName: String
        switch code {
        case "C48323": colorName = "black"
        case "C48333": colorName = "blue"
        case "C48332": colorName = "brown"
        case "C48324": colorName = "gray"
        case "C48329": colorName = "green"
        case "C48331": colorName = "orange"
        case "C48328": colorName = "pink"
        case "C48327": colorName = "purple"
        case "C48326": colorName = "red"
        case "C48334": colorName = "turquoise"
        case "C48325": colorName = "white"
        case "C48330": colorName = "yellow"
        default: return nil
        }
        
        if let match = colors.first(where: { $0.name.lowercased().contains(colorName) }) {
            return match
        }
        
        switch colorName {
        case "yellow":
            return colors.first(where: { $0.colorHex.uppercased() == "#F59E0B" || $0.name.lowercased().contains("yellow") })
        case "turquoise", "blue":
            return colors.first(where: { $0.colorHex.uppercased() == "#14B8A6" || $0.colorHex.uppercased() == "#3B82F6" || $0.name.lowercased().contains("teal") || $0.name.lowercased().contains("blue") })
        case "purple", "pink":
            return colors.first(where: { $0.colorHex.uppercased() == "#8B5CF6" || $0.name.lowercased().contains("purple") })
        case "red", "orange", "brown":
            return colors.first(where: { $0.colorHex.uppercased() == "#EF4444" || $0.name.lowercased().contains("red") })
        case "green":
            return colors.first(where: { $0.colorHex.uppercased() == "#10B981" || $0.name.lowercased().contains("green") })
        default:
            return nil
        }
    }
    
    private func validateAndSave() {
        if let pill = pill, pill.dosage != dosage {
            // Dosage changed! Capture justification note
            dosageChangeReason = ""
            showingChangeNoteSheet = true
        } else {
            savePill()
        }
    }
    
    private func savePill() {
        if let pill = pill {
            pill.name = name
            pill.dosage = dosage
            pill.scheduleTime = scheduleTime
            pill.pillColor = selectedColor
            
            pill.ndc = ndc
            pill.splSetId = splSetId
            pill.imageUrlString = imageUrlString
            pill.imprint = imprint
            pill.shapeName = shapeSelection.rawValue
            pill.colorDescription = colorDescription
        } else {
            let newPill = Pill(
                name: name,
                dosage: dosage,
                scheduleTime: scheduleTime,
                ndc: ndc,
                splSetId: splSetId,
                imageUrlString: imageUrlString,
                imprint: imprint,
                shapeName: shapeSelection.rawValue,
                colorDescription: colorDescription
            )
            newPill.pillColor = selectedColor
            modelContext.insert(newPill)
        }
        
        try? modelContext.save()
        dismiss()
    }
    
    private var dosageChangeNoteSheet: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient
                    .ignoresSafeArea()
                
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DOSAGE CHANGE REQUIRED")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.textSecondary)
                        
                        Text("Explain why the dosage is changing. This note will be recorded in your drug history log.")
                            .font(.footnote)
                            .foregroundColor(Theme.textSecondary)
                    }
                    
                    HStack(spacing: 20) {
                        VStack(alignment: .leading) {
                            Text("OLD DOSAGE")
                                .font(.caption2)
                                .foregroundColor(Theme.textSecondary)
                            Text(pill?.dosage ?? "")
                                .font(.body)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        
                        Image(systemName: "arrow.right")
                            .foregroundColor(Color(hex: "#38BDF8"))
                        
                        VStack(alignment: .leading) {
                            Text("NEW DOSAGE")
                                .font(.caption2)
                                .foregroundColor(Theme.textSecondary)
                            Text(dosage)
                                .font(.body)
                                .foregroundColor(.white)
                                .fontWeight(.bold)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.cardBackground)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.cardBorder, lineWidth: 1)
                    )
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("JUSTIFICATION NOTE")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.textSecondary)
                        
                        TextEditor(text: $dosageChangeReason)
                            .frame(height: 120)
                            .padding(8)
                            .background(Theme.cardBackground)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Theme.cardBorder, lineWidth: 1)
                            )
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    Button(action: saveWithChangeNote) {
                        Text("Save & Log Note")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding()
                            .background(
                                dosageChangeReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? LinearGradient(colors: [Color.gray.opacity(0.3)], startPoint: .leading, endPoint: .trailing)
                                : Theme.accentGradient
                            )
                            .cornerRadius(12)
                    }
                    .disabled(dosageChangeReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
            }
            .navigationTitle("Change Justification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back") {
                        showingChangeNoteSheet = false
                    }
                    .foregroundColor(Color(hex: "#38BDF8"))
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
    
    private func saveWithChangeNote() {
        guard let pill = pill else { return }
        
        let changeLog = DoseChangeLog(
            pillName: pill.name,
            oldDosage: pill.dosage,
            newDosage: dosage,
            timestamp: Date(),
            reason: dosageChangeReason
        )
        changeLog.pill = pill
        modelContext.insert(changeLog)
        
        savePill()
        showingChangeNoteSheet = false
    }
}
