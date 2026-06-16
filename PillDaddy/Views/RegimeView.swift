import SwiftUI
import SwiftData

struct RegimeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Pill.scheduleTime) private var pills: [Pill]
    @Query private var doseLogs: [DoseLog]
    
    @State private var selectedDate = Date()
    
    // Calendar days: 3 days before today, today, 3 days after
    private var calendarDays: [Date] {
        let calendar = Calendar.current
        let today = Date()
        return (-3...3).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: today)
        }
    }
    
    // Group active pills by their color configuration
    private var sortedColors: [PillColor] {
        let colorsWithPills = Set(pills.compactMap { $0.pillColor })
        return colorsWithPills.sorted { $0.name < $1.name }
    }
    
    private var uncategorizedPills: [Pill] {
        pills.filter { $0.pillColor == nil }
    }
    
    // Progress computations
    private var totalPillsDue: Int {
        pills.count
    }
    
    private var takenPillsCount: Int {
        return pills.filter { pill in
            isPillTakenOnSelectedDate(pill)
        }.count
    }
    
    private var progressPercentage: Double {
        guard totalPillsDue > 0 else { return 0.0 }
        return Double(takenPillsCount) / Double(totalPillsDue)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Custom Horizontal Calendar Stripe
                    calendarStripeView
                        .padding(.vertical, 12)
                    
                    ScrollView {
                        VStack(spacing: 20) {
                            // Progress Header Panel
                            progressHeaderCard
                                .padding(.horizontal)
                            
                            // Regime Sections
                            if pills.isEmpty {
                                emptyStateCard
                                    .padding(.horizontal)
                            } else {
                                VStack(spacing: 16) {
                                    // Render Category Groups
                                    ForEach(sortedColors) { color in
                                        let categoryPills = pills.filter { $0.pillColor?.id == color.id }
                                        if !categoryPills.isEmpty {
                                            regimeSection(title: color.name, colorHex: color.colorHex, pills: categoryPills)
                                        }
                                    }
                                    
                                    // Render Uncategorized
                                    if !uncategorizedPills.isEmpty {
                                        regimeSection(title: "Other Medications", colorHex: "#94A3B8", pills: uncategorizedPills)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle(navigationTitleText)
        }
    }
    
    // MARK: - Subviews
    
    private var navigationTitleText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(selectedDate) {
            return "Today's Regime"
        } else if calendar.isDateInYesterday(selectedDate) {
            return "Yesterday's Regime"
        } else if calendar.isDateInTomorrow(selectedDate) {
            return "Tomorrow's Regime"
        } else {
            return selectedDate.formatted(.dateTime.month().day())
        }
    }
    
    private var calendarStripeView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(calendarDays, id: \.self) { date in
                    let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
                    let isToday = Calendar.current.isDateInToday(date)
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                            selectedDate = date
                        }
                    }) {
                        VStack(spacing: 6) {
                            Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(isSelected ? .white : Theme.textSecondary)
                            
                            Text(date.formatted(.dateTime.day()))
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 38, height: 38)
                                .background {
                                    if isSelected {
                                        Theme.accentGradient
                                    } else if isToday {
                                        Color.white.opacity(0.12)
                                    }
                                }
                                .clipShape(Circle())
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(isSelected ? Theme.cardBackground : Color.clear)
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(isSelected ? Theme.cardBorder : Color.clear, lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    private var progressHeaderCard: some View {
        HStack(spacing: 20) {
            // Animating Progress Ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 8)
                
                Circle()
                    .trim(from: 0.0, to: CGFloat(min(progressPercentage, 1.0)))
                    .stroke(
                        Theme.accentGradient,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(Angle(degrees: -90))
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progressPercentage)
                
                VStack(spacing: 1) {
                    Text("\(Int(progressPercentage * 100))%")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    Text("\(takenPillsCount)/\(totalPillsDue)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .frame(width: 76, height: 76)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(progressTitle)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text(progressSubtitle)
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(2)
            }
            
            Spacer()
        }
        .glassmorphicCard()
    }
    
    private var progressTitle: String {
        if progressPercentage >= 1.0 && totalPillsDue > 0 {
            return "All Done!"
        } else if progressPercentage > 0 {
            return "Keep it up!"
        } else {
            return "Ready to start?"
        }
    }
    
    private var progressSubtitle: String {
        if totalPillsDue == 0 {
            return "No medications scheduled. Go to Cabinet to add some."
        } else if progressPercentage >= 1.0 {
            return "You have taken all scheduled medications for this day."
        } else {
            let remaining = totalPillsDue - takenPillsCount
            return "\(remaining) more medication\(remaining > 1 ? "s" : "") left to take today."
        }
    }
    
    private var emptyStateCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accentGradient)
                .opacity(0.7)
            
            Text("No Regime Configured")
                .font(.headline)
                .foregroundColor(.white)
            
            Text("Add medications in your Cabinet to start tracking your daily regime.")
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .glassmorphicCard()
    }
    
    private func regimeSection(title: String, colorHex: String, pills: [Pill]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: colorHex))
                    .frame(width: 10, height: 10)
                    .shadow(color: Color(hex: colorHex).opacity(0.6), radius: 3)
                
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Theme.textSecondary)
                    .tracking(1)
            }
            .padding(.leading, 4)
            
            VStack(spacing: 12) {
                ForEach(pills) { pill in
                    let isTaken = isPillTakenOnSelectedDate(pill)
                    
                    HStack(spacing: 16) {
                        // Custom animated checkbox
                        Button(action: {
                            toggleDose(pill)
                        }) {
                            ZStack {
                                Circle()
                                    .stroke(isTaken ? Color(hex: colorHex) : Color.white.opacity(0.18), lineWidth: 2)
                                    .frame(width: 28, height: 28)
                                
                                if isTaken {
                                    Circle()
                                        .fill(Color(hex: colorHex))
                                        .frame(width: 18, height: 18)
                                        .transition(.scale.combined(with: .opacity))
                                    
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isTaken)
                        
                        PillImageView(imageUrlString: pill.imageUrlString, defaultColorHex: colorHex, shapeName: pill.shapeName, size: 40)
                            .opacity(isTaken ? 0.6 : 1.0)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(pill.name)
                                .font(.body)
                                .fontWeight(.semibold)
                                .foregroundColor(isTaken ? Theme.textSecondary : .white)
                                .strikethrough(isTaken, color: Theme.textSecondary)
                            
                            Text(pill.dosage)
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                        }
                        
                        Spacer()
                        
                        Text(pill.scheduleTime.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.04))
                            .cornerRadius(8)
                    }
                    .padding()
                    .background(Theme.cardBackground)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Theme.cardBorder, lineWidth: 1)
                    )
                }
            }
        }
    }
    
    // MARK: - Logic
    
    private func isPillTakenOnSelectedDate(_ pill: Pill) -> Bool {
        let calendar = Calendar.current
        return doseLogs.contains { log in
            if let logPill = log.pill, logPill.id == pill.id {
                return calendar.isDate(log.timestamp, inSameDayAs: selectedDate)
            }
            return false
        }
    }
    
    private func toggleDose(_ pill: Pill) {
        let calendar = Calendar.current
        let matchingLogs = doseLogs.filter { log in
            if let logPill = log.pill, logPill.id == pill.id {
                return calendar.isDate(log.timestamp, inSameDayAs: selectedDate)
            }
            return false
        }
        
        if let existingLog = matchingLogs.first {
            // Delete log
            modelContext.delete(existingLog)
        } else {
            // Combine selected date (year/month/day) with pill's scheduled time (hour/minute)
            let logTimestamp = dateForLog(selectedDate: selectedDate, scheduledTime: pill.scheduleTime)
            
            let colorHex = pill.pillColor?.colorHex ?? "#8E8E93"
            let log = DoseLog(
                pillName: pill.name,
                dosage: pill.dosage,
                colorHex: colorHex,
                timestamp: logTimestamp,
                status: "taken"
            )
            log.pill = pill
            modelContext.insert(log)
        }
        
        try? modelContext.save()
    }
    
    private func dateForLog(selectedDate: Date, scheduledTime: Date) -> Date {
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: scheduledTime)
        
        var combined = DateComponents()
        combined.year = dateComponents.year
        combined.month = dateComponents.month
        combined.day = dateComponents.day
        combined.hour = timeComponents.hour
        combined.minute = timeComponents.minute
        
        return calendar.date(from: combined) ?? selectedDate
    }
}
