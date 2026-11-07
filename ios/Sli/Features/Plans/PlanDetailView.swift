import SwiftUI
import MapKit

struct PlanDetailView: View {
    @Environment(AppState.self) private var state
    let planID: String
    @State private var status: MyStatus = .notLeft

    enum MyStatus { case notLeft, onMyWay, here }

    private var plan: Plan? { state.plans.first { $0.id == planID } }

    var body: some View {
        if let plan {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    mapHeader(plan)
                    VStack(alignment: .leading, spacing: 20) {
                        titleBlock(plan)
                        statusButtons(plan)
                        GetThereCard(plan: plan)
                        SectionHeader(title: "Who's coming", trailing: "\(plan.attendees.filter { $0.rsvp == .going }.count) going")
                        GlassCard {
                            VStack(spacing: 14) { ForEach(plan.attendees) { AttendeeRow(attendee: $0, tint: plan.tint) } }
                        }
                        if plan.timeOptions.count > 1 {
                            SectionHeader(title: "Pick a time")
                            VStack(spacing: 10) {
                                ForEach(plan.timeOptions) { option in
                                    TimeVoteRow(option: option, total: plan.attendees.count + 1, tint: plan.tint) {
                                        withAnimation(.bouncy) { state.vote(plan: plan, option: option) }
                                    }
                                }
                            }
                        }
                        GlassCard(tint: Theme.accent) {
                            Label("Everyone who arrives by public transport earns +50 XP squad bonus", systemImage: "leaf.fill")
                                .font(.subheadline.weight(.medium))
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 32)
            }
            .ignoresSafeArea(edges: .top)
            .background(AuroraBackground(tint: plan.tint))
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { } label: { Image(systemName: "bubble.left.and.bubble.right.fill") }
                    Button { } label: { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
    }

    private func mapHeader(_ plan: Plan) -> some View {
        Map(initialPosition: .region(.init(center: plan.location.coordinate,
                                           span: .init(latitudeDelta: 0.02, longitudeDelta: 0.02))),
            interactionModes: []) {
            Annotation(plan.placeName, coordinate: plan.location.coordinate) {
                Image(systemName: plan.symbol)
                    .font(.title3).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(plan.tint, in: .circle)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 3))
            }
            ForEach(plan.attendees.filter { !$0.arrived }) { a in
                Annotation(a.friend.name, coordinate: a.friend.location.coordinate) {
                    AvatarView(name: a.friend.name, seed: a.friend.seed, size: 30, ring: a.friend.ringColor ?? .white)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .frame(height: 300)
        .mask(LinearGradient(stops: [.init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
    }

    private func titleBlock(_ plan: Plan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(plan.title).font(.largeTitle.weight(.bold)).fontDesign(.rounded)
            Label(plan.placeName, systemImage: "mappin.and.ellipse").foregroundStyle(.secondary)
            Label(plan.date.formatted(.dateTime.weekday(.wide).day().month().hour().minute()), systemImage: "clock")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    private func statusButtons(_ plan: Plan) -> some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                statusButton("Not left", symbol: "house.fill", value: .notLeft, tint: .gray)
                statusButton("On my way", symbol: "figure.walk.motion", value: .onMyWay, tint: plan.tint)
                statusButton("I'm here", symbol: "checkmark.seal.fill", value: .here, tint: Theme.accent)
            }
        }
        .sensoryFeedback(.success, trigger: status == .here)
    }

    private func statusButton(_ title: String, symbol: String, value: MyStatus, tint: Color) -> some View {
        Button { withAnimation(.bouncy) { status = value } } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .glassEffect(status == value ? .regular.tint(tint.opacity(0.8)).interactive() : .regular.interactive(),
                     in: .rect(cornerRadius: 20))
    }
}

private struct AttendeeRow: View {
    let attendee: PlanAttendee
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(name: attendee.friend.name, seed: attendee.friend.seed, size: 40, ring: attendee.friend.ringColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(attendee.friend.name).font(.subheadline.weight(.semibold))
                Text(attendee.arrived ? "Arrived" : attendee.friend.status.label)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            switch (attendee.arrived, attendee.etaMinutes, attendee.rsvp) {
            case (true, _, _):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent).font(.title3)
            case let (false, eta?, _):
                MinutesLabel(minutes: eta)
            case (_, _, .maybe):
                Text("Maybe").font(.caption.weight(.bold)).foregroundStyle(Theme.gold)
            case (_, _, .invited):
                Text("Invited").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            default:
                Text("Going").font(.caption.weight(.bold)).foregroundStyle(tint)
            }
        }
    }
}

private struct TimeVoteRow: View {
    let option: TimeOption
    let total: Int
    let tint: Color
    let onVote: () -> Void

    private var voted: Bool { option.voterIDs.contains("me") }

    var body: some View {
        Button(action: onVote) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(option.date.formatted(.dateTime.weekday(.wide).hour().minute())).font(.headline)
                    GeometryReader { geo in
                        Capsule().fill(.white.opacity(0.1))
                            .overlay(alignment: .leading) {
                                Capsule().fill(tint)
                                    .frame(width: geo.size.width * Double(option.voterIDs.count) / Double(max(total, 1)))
                            }
                    }
                    .frame(height: 6)
                }
                Text("\(option.voterIDs.count)").font(.title3.weight(.heavy)).fontDesign(.rounded)
                    .contentTransition(.numericText()).frame(width: 30)
                Image(systemName: voted ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(voted ? tint : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(14)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        .sensoryFeedback(.selection, trigger: voted)
    }
}
