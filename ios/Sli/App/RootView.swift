import SwiftUI

enum AppTab: Hashable { case explore, plans, friends, you, search }

struct RootView: View {
    @Environment(AppState.self) private var state
    @State private var tab: AppTab = {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "tab") {
        case "plans": return .plans
        case "friends": return .friends
        case "you": return .you
        default: return .explore
        }
        #else
        return .explore
        #endif
    }()
    @State private var showCommute = false

    var body: some View {
        TabView(selection: $tab) {
            Tab("Explore", systemImage: "map.fill", value: .explore) { ExploreView() }
            Tab("Plans", systemImage: "calendar", value: .plans) { PlansView() }
                .badge(state.livePlan == nil ? 0 : 1)
            Tab("Friends", systemImage: "person.2.fill", value: .friends) { FriendsView() }
            Tab("You", systemImage: "sparkles", value: .you) { ProfileView() }
            Tab("Search", systemImage: "magnifyingglass", value: .search, role: .search) { SearchView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            NextUpAccessory {
                if state.livePlan != nil { tab = .plans } else { showCommute = true }
            }
        }
        .sheet(isPresented: $showCommute) { CommuteView() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(45))
                await state.refreshCommute()
            }
        }
    }
}

private struct NextUpAccessory: View {
    @Environment(AppState.self) private var state
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let plan = state.livePlan {
                    Image(systemName: plan.symbol).foregroundStyle(plan.tint)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(plan.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text("\(plan.attendees.filter(\.arrived).count)/\(plan.attendees.count) there · starts \(plan.date, format: .relative(presentation: .named, unitsStyle: .abbreviated))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    LivePulse(color: plan.tint)
                } else if let next = state.nextCommuteJourney {
                    ModeBadge(mode: next.mode, route: next.route, compact: true)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let leaveIn = next.leaveAt.timeIntervalSince(context.date)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(LeaveIn.headline(leaveIn))
                                .font(.subheadline.weight(.heavy)).foregroundStyle(LeaveIn.color(leaveIn))
                            Text("\(next.fromStop) \(next.departs, format: .dateTime.hour().minute())")
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                    Image(systemName: next.status.symbol).foregroundStyle(next.status.color)
                        .accessibilityLabel(next.status.title)
                } else if let next = state.nextDeparture {
                    ModeBadge(mode: next.arrival.mode, route: next.arrival.route, compact: true)
                    Text(next.stop.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Spacer()
                    MinutesLabel(minutes: next.arrival.minutes)
                } else {
                    Label("Slí", systemImage: "point.topright.arrow.triangle.backward.to.point.bottomleft.scurvepath")
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }
}
