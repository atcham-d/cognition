import SwiftUI

/// Real "how do I get there and when do I leave" for a plan, from your home stop (or the map centre).
struct GetThereCard: View {
    @Environment(AppState.self) private var state
    let plan: Plan
    @State private var trip: TripPlan?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Get me there", trailing: "from \(state.tripOriginName)")
            if let trip, let best = trip.options.first {
                GlassCard(tint: plan.tint) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(trip.late ? "Leave now: earliest arrival \(best.arriveAtDoor.formatted(date: .omitted, time: .shortened))"
                                       : "Leave by \(best.leaveAt.formatted(date: .omitted, time: .shortened))")
                            .font(.title2.weight(.heavy)).fontDesign(.rounded)
                            .foregroundStyle(trip.late ? Theme.ember : .primary)
                        HStack(spacing: 6) {
                            Label("\(best.walkToMinutes)m", systemImage: "figure.walk")
                            Image(systemName: "chevron.right").font(.caption2)
                            ModeBadge(mode: best.mode, route: best.route, compact: true)
                            Image(systemName: "chevron.right").font(.caption2)
                            Label("\(best.walkFromMinutes)m", systemImage: "figure.walk")
                            Spacer()
                            StatusChip(status: best.status, delayMinutes: best.delayMinutes)
                        }
                        .font(.caption.weight(.semibold))
                        Text("\(best.fromStop) \(best.departs.formatted(date: .omitted, time: .shortened)) → \(best.toStop) · there \(best.arriveAtDoor.formatted(date: .omitted, time: .shortened))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if trip.options.count > 1 {
                    ForEach(trip.options.dropFirst()) { JourneyRow(journey: $0) }
                }
            } else if let trip {
                GlassCard { Label("No direct route. Walking takes about \(trip.walkOnlyMinutes) min.", systemImage: "figure.walk") }
            } else if failed {
                GlassCard { Label("Couldn't reach the transit server", systemImage: "wifi.exclamationmark") }
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .task(id: plan.id) {
            do { trip = try await state.trip(to: plan) } catch { failed = true }
        }
    }
}
