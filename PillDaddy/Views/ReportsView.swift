import SwiftUI
import SwiftData
import Charts

struct ReportsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Pill.name) private var pills: [Pill]
    @Query(sort: \DoseLog.timestamp, order: .reverse) private var doseLogs: [DoseLog]
    @Query(sort: \DoseChangeLog.timestamp, order: .reverse) private var doseChangeLogs: [DoseChangeLog]
    
    @State private var selectedSegment = 0
    @State private var searchLogQuery = ""
    
    struct DayAdherence: Identifiable {
        let id = UUID()
        let date: Date
        let percentage: Double
        
        var dayLabel: String {
            date.formatted(.dateTime.weekday(.abbreviated))
        }
    }
    
    // Compute last 7 days of pill adherence
    private var last7DaysAdherence: [DayAdherence] {
        let calendar = Calendar.current
        let today = Date()
        
        return (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            
            let total = pills.count
            guard total > 0 else {
                return DayAdherence(date: date, percentage: 0.0)
            }
            
            let taken = pills.filter { pill in
                doseLogs.contains { log in
                    if let logPill = log.pill, logPill.id == pill.id {
                        return calendar.isDate(log.timestamp, inSameDayAs: date)
                    }
                    return false
                }
            }.count
            
            let percentage = Double(taken) / Double(total)
            return DayAdherence(date: date, percentage: percentage)
        }
    }
    
    // Computed statistics
    private var weeklyAverageAdherence: Double {
        let data = last7DaysAdherence
        guard !data.isEmpty else { return 0 }
        let sum = data.reduce(0.0) { $0 + $1.percentage }
        return sum / Double(data.count)
    }
    
    private var totalTakenDoses: Int {
        doseLogs.count
    }
    
    private var filteredDoseLogs: [DoseLog] {
        if searchLogQuery.isEmpty {
            return doseLogs
        } else {
            return doseLogs.filter { $0.pillName.localizedCaseInsensitiveContains(searchLogQuery) }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    Picker("Section", selection: $selectedSegment) {
                        Text("Adherence").tag(0)
                        Text("Dose Notes").tag(1)
                        Text("Logs").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    ScrollView {
                        VStack(spacing: 20) {
                            switch selectedSegment {
                            case 0:
                                adherenceView
                            case 1:
                                doseNotesView
                            default:
                                logHistoryView
                            }
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Analytics")
        }
    }
    
    // MARK: - Adherence Tab View
    
    private var adherenceView: some View {
        VStack(spacing: 20) {
            // Chart Card
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WEEKLY ADHERENCE")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.textSecondary)
                    
                    Text("\(Int(weeklyAverageAdherence * 100))% Avg Adherence")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                
                if pills.isEmpty {
                    VStack {
                        Spacer()
                        Text("No pills logged. Setup cabinet to view charts.")
                            .font(.footnote)
                            .foregroundColor(Theme.textSecondary)
                        Spacer()
                    }
                    .frame(height: 200)
                } else {
                    Chart {
                        ForEach(last7DaysAdherence) { day in
                            // Translucent Area under line
                            AreaMark(
                                x: .value("Day", day.dayLabel),
                                y: .value("Adherence", day.percentage)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "#38BDF8").opacity(0.4), Color(hex: "#818CF8").opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.catmullRom)
                            
                            // Glowing Line
                            LineMark(
                                x: .value("Day", day.dayLabel),
                                y: .value("Adherence", day.percentage)
                            )
                            .foregroundStyle(Theme.accentGradient)
                            .lineStyle(StrokeStyle(lineWidth: 3))
                            .interpolationMethod(.catmullRom)
                            
                            // Points
                            PointMark(
                                x: .value("Day", day.dayLabel),
                                y: .value("Adherence", day.percentage)
                            )
                            .foregroundStyle(Color(hex: "#38BDF8"))
                        }
                    }
                    .chartYScale(domain: 0...1.0)
                    .chartYAxis {
                        AxisMarks(values: [0.0, 0.25, 0.5, 0.75, 1.0]) { value in
                            AxisGridLine()
                                .foregroundStyle(Color.white.opacity(0.06))
                            AxisValueLabel {
                                if let val = value.as(Double.self) {
                                    Text("\(Int(val * 100))%")
                                        .foregroundColor(Theme.textSecondary)
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks { value in
                            AxisGridLine()
                                .foregroundStyle(Color.clear)
                            AxisValueLabel {
                                if let dayLabel = value.as(String.self) {
                                    Text(dayLabel)
                                        .foregroundColor(Theme.textSecondary)
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                    .frame(height: 200)
                }
            }
            .glassmorphicCard()
            .padding(.horizontal)
            
            // Stats Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.accentGradient)
                    
                    Text("Total Taken")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                    
                    Text("\(totalTakenDoses) doses")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .glassmorphicCard()
                
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.doc.horizontal.fill")
                        .font(.title2)
                        .foregroundColor(Theme.warningColor)
                    
                    Text("Active Pills")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                    
                    Text("\(pills.count) registered")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .glassmorphicCard()
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Dose Notes Tab View (Change Logs)
    
    private var doseNotesView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("DOSE CHANGES HISTORY")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(Theme.textSecondary)
                .padding(.horizontal)
            
            if doseChangeLogs.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "note.text")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    
                    Text("No Dosage Changes Logged")
                        .font(.subheadline)
                        .foregroundColor(.white)
                    
                    Text("Any dosage modifications made in the Cabinet will prompt for a note and appear here.")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .glassmorphicCard()
                .padding(.horizontal)
            } else {
                VStack(spacing: 12) {
                    ForEach(doseChangeLogs) { log in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(log.pillName)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                Spacer()
                                
                                Text(log.timestamp.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundColor(Theme.textSecondary)
                            }
                            
                            HStack(spacing: 8) {
                                Text(log.oldDosage)
                                    .font(.caption)
                                    .foregroundColor(Theme.textSecondary)
                                    .strikethrough()
                                
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundColor(Color(hex: "#38BDF8"))
                                
                                Text(log.newDosage)
                                    .font(.caption)
                                    .foregroundColor(Theme.successColor)
                                    .fontWeight(.semibold)
                            }
                            
                            Divider()
                                .background(Theme.cardBorder)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("REASON FOR CHANGE")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(Theme.textSecondary)
                                
                                Text(log.reason)
                                    .font(.footnote)
                                    .foregroundColor(.white.opacity(0.85))
                                    .lineLimit(nil)
                            }
                        }
                        .glassmorphicCard()
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Log History Tab View
    
    private var logHistoryView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("HISTORICAL TAKE LOGS")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(Theme.textSecondary)
                
                Spacer()
                
                Text("\(filteredDoseLogs.count) logs")
                    .font(.caption2)
                    .foregroundColor(Theme.textSecondary)
            }
            .padding(.horizontal)
            
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                TextField("Search by drug name...", text: $searchLogQuery)
                    .foregroundColor(.white)
                    .font(.subheadline)
                if !searchLogQuery.isEmpty {
                    Button(action: { searchLogQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(10)
            .background(Theme.cardBackground)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Theme.cardBorder, lineWidth: 1)
            )
            .padding(.horizontal)
            
            if filteredDoseLogs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundColor(.gray)
                    Text(searchLogQuery.isEmpty ? "No Logs Available" : "No results for '\(searchLogQuery)'")
                        .font(.footnote)
                        .foregroundColor(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                VStack(spacing: 12) {
                    ForEach(filteredDoseLogs) { log in
                        HStack(spacing: 16) {
                            Circle()
                                .fill(Color(hex: log.colorHex))
                                .frame(width: 12, height: 12)
                                .shadow(color: Color(hex: log.colorHex).opacity(0.4), radius: 3)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(log.pillName)
                                    .font(.body)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                Text(log.dosage)
                                    .font(.caption)
                                    .foregroundColor(Theme.textSecondary)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(log.timestamp.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption2)
                                    .foregroundColor(.white)
                                Text(log.timestamp.formatted(date: .omitted, time: .shortened))
                                    .font(.caption2)
                                    .foregroundColor(Theme.textSecondary)
                            }
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
                .padding(.horizontal)
            }
        }
    }
}
