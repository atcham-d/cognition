import SwiftUI

/// "When do I leave?": the next departure for your saved commute, with your walk to the stop
/// already counted, plus a Plan B in case the first one never shows.
struct CommuteView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let commute = state.commute {
                        routeHeader(commute)
                        if let next = state.nextCommuteJourney {
                            LeaveHero(journey: next)
                        } else if state.commuteLoading {
                            ProgressView().frame(maxWidth: .infinity, minHeight: 160)
                        } else {
                            GlassCard {
                                Label(state.commuteError ?? (state.commuteJourneys.isEmpty
                                      ? "No direct departures in the next 2 hours"
                                      : "Every direct departure in the next 2 hours is cancelled"),
                                      systemImage: "moon.zzz.fill")
                            }
                        }
                        if !state.commutePlanB.isEmpty {
                            SectionHeader(title: "Plan B", trailing: "if that one vanishes")
                            VStack(spacing: 10) {
                                ForEach(state.commutePlanB) { JourneyRow(journey: $0) }
                            }
                        }
                        Text("Times from \(state.transit.sourceLabel). \"Unconfirmed\" means the vehicle is due soon but isn't reporting its position.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        GlassCard(tint: Theme.accent) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("When do I leave?").font(.title2.weight(.bold)).fontDesign(.rounded)
                                Text("Save your usual trip once. Slí counts your walk to the stop and tells you when to head out.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Button("Set up my commute") { editing = true }.buttonStyle(.glassProminent)
                            }
                        }
                    }
                }
                .padding()
            }
            .background(AuroraBackground())
            .navigationTitle("Commute")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if state.commute != nil {
                        Button { Task { await state.swapCommute() } } label: {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                        .accessibilityLabel("Return trip")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Edit commute")
                }
                ToolbarItem(placement: .topBarTrailing) { Button(role: .close) { dismiss() } }
            }
            .refreshable { await state.refreshCommute() }
            .task { await state.refreshCommute() }
            .sheet(isPresented: $editing) { CommuteSetupView() }
        }
    }

    private func routeHeader(_ c: Commute) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(c.from.name) → \(c.to.name)").font(.title3.weight(.bold)).fontDesign(.rounded)
            Label("\(c.walkMinutes) min walk to the stop", systemImage: "figure.walk")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct LeaveHero: View {
    let journey: Journey

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let leaveIn = journey.leaveAt.timeIntervalSince(context.date)
            let tint = LeaveIn.color(leaveIn)
            VStack(alignment: .leading, spacing: 14) {
                Text(LeaveIn.headline(leaveIn))
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
                HStack(spacing: 8) {
                    ModeBadge(mode: journey.mode, route: journey.route)
                    Text("to \(journey.headsign)").font(.headline).lineLimit(1)
                    Spacer()
                    StatusChip(status: journey.status, delayMinutes: journey.delayMinutes)
                }
                Text("Departs \(journey.fromStop)\(journey.fromCode.isEmpty ? "" : " (stop \(journey.fromCode))") at \(journey.departs, format: .dateTime.hour().minute()) · arrive \(journey.toStop) \(journey.arriveAtDoor, format: .dateTime.hour().minute())")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(tint.opacity(0.25)), in: .rect(cornerRadius: 32))
        }
    }
}

enum LeaveIn {
    static func headline(_ seconds: TimeInterval) -> String {
        if seconds < -30 { return "Run!" }
        if seconds < 60 { return "Leave now" }
        return "Leave in \(Int(seconds / 60)) min"
    }

    static func color(_ seconds: TimeInterval) -> Color {
        seconds < 60 ? Theme.ember : seconds < 5 * 60 ? Theme.gold : Theme.accent
    }
}

struct StatusChip: View {
    let status: ArrivalStatus
    var delayMinutes: Int? = nil

    var body: some View {
        Label(text, systemImage: status.symbol)
            .font(.caption2.weight(.bold))
            .foregroundStyle(status.color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .glassEffect(.regular.tint(status.color.opacity(0.15)), in: .capsule)
            .accessibilityHint(status.explanation)
    }

    private var text: String {
        if status == .live, let d = delayMinutes, d != 0 { return d > 0 ? "Live · \(d) min late" : "Live · \(-d) min early" }
        return status.title
    }
}

struct JourneyRow: View {
    let journey: Journey

    var body: some View {
        HStack(spacing: 12) {
            ModeBadge(mode: journey.mode, route: journey.route).frame(minWidth: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text("Leave \(journey.leaveAt, format: .dateTime.hour().minute())").font(.headline)
                Text("\(journey.fromStop) \(journey.departs, format: .dateTime.hour().minute()) → \(journey.toStop) \(journey.arriveAtDoor, format: .dateTime.hour().minute())")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            StatusChip(status: journey.status, delayMinutes: journey.delayMinutes)
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .opacity(journey.status == .cancelled ? 0.5 : 1)
    }
}

struct CommuteSetupView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var from: Stop?
    @State private var to: Stop?
    @State private var walk = 5

    var body: some View {
        NavigationStack {
            Form {
                Section("From") { StopPicker(selection: $from, prompt: "Stop name or number on the pole") }
                Section("To") { StopPicker(selection: $to, prompt: "Where you're going") }
                Section("Walk to the stop") {
                    Stepper("\(walk) min", value: $walk, in: 0...30)
                }
            }
            .navigationTitle("My commute")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        guard let from, let to else { return }
                        state.commute = Commute(from: from, to: to, walkMinutes: walk)
                        Task { await state.refreshCommute() }
                        dismiss()
                    }
                    .disabled(from == nil || to == nil)
                }
            }
            .onAppear {
                from = from ?? state.commute?.from
                to = to ?? state.commute?.to
                walk = state.commute?.walkMinutes ?? walk
            }
        }
    }
}

private struct StopPicker: View {
    @Environment(AppState.self) private var state
    @Binding var selection: Stop?
    let prompt: String
    @State private var query = ""
    @State private var results: [Stop] = []

    var body: some View {
        if let stop = selection {
            HStack {
                ForEach(stop.modes, id: \.self) { ModeBadge(mode: $0, compact: true) }
                Text(stop.name).font(.headline)
                Spacer()
                Button("Change") { selection = nil; query = "" }
            }
        } else {
            TextField(prompt, text: $query)
                .autocorrectionDisabled()
                .task(id: query) {
                    guard query.count >= 2 else { results = []; return }
                    try? await Task.sleep(for: .milliseconds(250))
                    results = (try? await state.transit.searchStops(query)) ?? []
                }
            ForEach(results.prefix(6)) { stop in
                Button { selection = stop } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            ForEach(stop.modes, id: \.self) { ModeBadge(mode: $0, compact: true) }
                            Text(stop.name).font(.subheadline.weight(.semibold))
                        }
                        Text(stop.routes.prefix(6).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
