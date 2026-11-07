import SwiftUI

struct PlansView: View {
    @Environment(AppState.self) private var state
    @State private var creating = false
    @Namespace private var zoom

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let live = state.livePlan {
                        NavigationLink(value: live) { LivePlanCard(plan: live) }
                            .buttonStyle(.plain)
                            .matchedTransitionSource(id: live.id, in: zoom)
                    }
                    SectionHeader(title: "Coming up", trailing: "\(state.upcomingPlans.count)")
                    ForEach(state.upcomingPlans) { plan in
                        NavigationLink(value: plan) { PlanCard(plan: plan) }
                            .buttonStyle(.plain)
                            .matchedTransitionSource(id: plan.id, in: zoom)
                    }
                    suggestionCard
                }
                .padding()
            }
            .background(AuroraBackground(tint: Theme.ember))
            .navigationTitle("Plans")
            .navigationDestination(for: Plan.self) { plan in
                PlanDetailView(planID: plan.id)
                    .navigationTransition(.zoom(sourceID: plan.id, in: zoom))
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { creating = true } label: { Image(systemName: "plus") }
                        .buttonStyle(.glassProminent)
                }
            }
            .sheet(isPresented: $creating) { CreatePlanView() }
        }
    }

    private var suggestionCard: some View {
        GlassCard(tint: Theme.violet) {
            HStack(spacing: 14) {
                Image(systemName: "wand.and.sparkles")
                    .font(.title2)
                    .foregroundStyle(Theme.violet)
                    .symbolEffect(.wiggle, options: .repeat(.periodic(delay: 3)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fair meeting point").font(.headline)
                    Text("Niamh & Saoirse are both ~15 min from Grand Canal Dock. Plan something?")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("Plan") { creating = true }.buttonStyle(.glass)
            }
        }
    }
}

private struct LivePlanCard: View {
    let plan: Plan

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("LIVE", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.weight(.heavy))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .glassEffect(.regular.tint(plan.tint), in: .capsule)
                Spacer()
                Text(plan.date, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                    .font(.caption.weight(.semibold))
            }
            HStack(spacing: 12) {
                Image(systemName: plan.symbol).font(.largeTitle).foregroundStyle(plan.tint)
                VStack(alignment: .leading) {
                    Text(plan.title).font(.title2.weight(.bold)).fontDesign(.rounded)
                    Text(plan.placeName).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 10) {
                ForEach(plan.attendees) { a in
                    HStack {
                        AvatarView(name: a.friend.name, seed: a.friend.seed, size: 30, ring: a.friend.ringColor)
                        Text(a.friend.name.components(separatedBy: " ").first ?? "").font(.subheadline.weight(.medium))
                        Spacer()
                        if a.arrived {
                            Label("There", systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
                        } else if let eta = a.etaMinutes {
                            ProgressView(value: max(0, 1 - Double(eta) / 25)).frame(width: 70).tint(plan.tint)
                            Text("\(eta)m").font(.caption.weight(.bold)).monospacedDigit().frame(width: 30, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .padding(20)
        .glassEffect(.regular.tint(plan.tint.opacity(0.25)).interactive(), in: .rect(cornerRadius: 32))
    }
}

struct PlanCard: View {
    let plan: Plan

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 0) {
                Text(plan.date.formatted(.dateTime.weekday(.abbreviated))).font(.caption2.weight(.bold)).foregroundStyle(plan.tint)
                Text(plan.date.formatted(.dateTime.day())).font(.title.weight(.heavy)).fontDesign(.rounded)
            }
            .frame(width: 56, height: 64)
            .glassEffect(.regular.tint(plan.tint.opacity(0.3)), in: .rect(cornerRadius: 18))

            VStack(alignment: .leading, spacing: 4) {
                Text(plan.title).font(.headline)
                Label(plan.placeName, systemImage: "mappin.and.ellipse")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: -6) {
                    ForEach(plan.attendees.prefix(4)) { AvatarView(name: $0.friend.name, seed: $0.friend.seed, size: 22) }
                    if plan.timeOptions.count > 1 {
                        Text("Voting on time").font(.caption2.weight(.semibold)).foregroundStyle(Theme.gold).padding(.leading, 12)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
        }
        .padding(14)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Theme.cardRadius))
    }
}
