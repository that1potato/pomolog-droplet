//
//  SummitWidget.swift
//  Pomodorolog
//
//  The summit on the shelf: the peak you're climbing, the trail with a tomato
//  for each focus, and how far there is to go. Alone it shows the whole scene;
//  sharing a row it shows the trail, the climber and a percentage.
//

import DroppyKit
import SwiftUI

extension PomodorologDroplet: ShelfWidgetProviding {
    static let summitWidgetID: ShelfWidgetID = "summit"

    public var widgetDescriptors: [ShelfWidgetDescriptor] {
        [
            ShelfWidgetDescriptor(
                id: Self.summitWidgetID,
                title: "Summit",
                systemImage: "mountain.2.fill",
                layoutTraits: ShelfWidgetLayoutTraits(
                    preferredSoloWidth: 440,
                    preferredPairedWidth: 218,
                    contentHeight: .fixed(212)
                ),
                searchKeywords: ["pomodoro", "summit", "climb", "tomato", "focus", "pomolog"]
            )
        ]
    }

    public func makeWidgetView(_ id: ShelfWidgetID, context: ShelfWidgetContext) -> AnyView {
        AnyView(SummitWidget(droplet: self, context: context))
    }
}

/// What the widget shows, worked out from the rewards. A plain value, so the
/// wording can be tested.
struct SummitWidgetModel: Equatable {
    enum State: Equatable {
        case climbing
        /// Nothing logged yet.
        case empty
        /// Droppy's Pomodoro can't be read, so nothing new is logged.
        case notLogging
    }

    let scene: SummitScene
    let state: State
    let todayTomatoes: Int
    let todayJars: Int
    /// Focus sessions to the top, at the pace of the last ten tomatoes of 10
    /// minutes or more: a quick test or a session ended early doesn't set the
    /// pace. With none yet, a 25-minute focus started from a break.
    let sessionsToTop: Int

    init(rewards: RewardsSnapshot, today: String, live: ClimbStep?, logging: Bool) {
        scene = SummitScene(rewards: rewards, today: today, live: live)
        let day = rewards.pantry.day(today)
        todayTomatoes = day.tomatoes
        todayJars = day.jars
        let tomatoes = Set(rewards.pantry.tomatoes.map(\.recordID))
        let recent = rewards.climb.steps
            .filter { tomatoes.contains($0.recordID) && $0.baseMetres >= ClimbRules.metres(seconds: 600) }
            .suffix(10)
        let pace = recent.isEmpty ? 300 : recent.reduce(0) { $0 + $1.metres } / Double(recent.count)
        let toGo = scene.peak.height - scene.climbed
        sessionsToTop = max(1, Int((toGo / max(pace, 1)).rounded()))
        if !logging {
            state = .notLogging
        } else if rewards.climb.steps.isEmpty, live == nil {
            state = .empty
        } else {
            state = .climbing
        }
    }

    /// `2,529 of 4,808 m`.
    var altitudeText: String {
        "\(Self.metres(scene.climbed)) of \(Self.metres(scene.peak.height)) m"
    }

    /// `53%`.
    var percentText: String {
        "\(Int((scene.fraction * 100).rounded(.down)))%"
    }

    /// The trailing line of the full footer.
    var statusText: String {
        switch state {
        case .notLogging:
            return "Not logging, see Settings"
        case .empty:
            return "Start a focus to begin the climb"
        case .climbing:
            return sessionsToTop == 1 ? "One more session to the top" : "Summit in about \(sessionsToTop) sessions"
        }
    }

    /// `Mont Blanc`, and `Mont Blanc, ascent 2` after the first time up.
    var peakTitle: String {
        scene.ascent > 1 ? "\(scene.peak.name), ascent \(scene.ascent)" : scene.peak.name
    }

    static func metres(_ value: Double) -> String {
        Int(value.rounded(.down)).formatted()
    }
}

private struct SummitWidget: View {
    @ObservedObject var droplet: PomodorologDroplet
    let context: ShelfWidgetContext

    var body: some View {
        // Every so often, so the climber moves during a focus.
        TimelineView(.periodic(from: .now, by: 15)) { timeline in
            let model = SummitWidgetModel(
                rewards: droplet.rewards,
                today: droplet.today,
                live: droplet.liveStep(at: timeline.date),
                logging: droplet.hookStatus == .logging || droplet.isShowingSample
            )
            VStack(alignment: .leading, spacing: DroppySpacing.sm) {
                header(model)
                MountainSceneView(scene: model.scene, showsMarkers: !context.isCompact)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if context.isCompact {
                    compactFooter(model)
                } else {
                    footer(model)
                }
            }
            .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
            .padding(context.contentInsets)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func header(_ model: SummitWidgetModel) -> some View {
        HStack(spacing: DroppySpacing.xsm) {
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 12, weight: .medium))
            Text(verbatim: model.peakTitle)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: DroppySpacing.sm)
            if !context.isCompact {
                Text(verbatim: model.altitudeText)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                    .lineLimit(1)
            }
            Button {
                droplet.openExpeditionLog()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(DroppyCircleButtonStyle(size: 24))
            .accessibilityLabel("Open the expedition log")
        }
    }

    private func footer(_ model: SummitWidgetModel) -> some View {
        HStack(spacing: DroppySpacing.md) {
            HStack(spacing: DroppySpacing.xsm) {
                TomatoGlyph()
                Text(verbatim: "\(model.todayTomatoes) today")
                    .monospacedDigit()
            }
            HStack(spacing: DroppySpacing.xsm) {
                JarGlyph()
                Text(verbatim: TimerFormat.count(model.todayJars, "jar", "jars"))
                    .monospacedDigit()
            }
            Spacer(minLength: DroppySpacing.sm)
            Text(verbatim: model.statusText)
                .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                .lineLimit(1)
        }
        .font(.system(size: 11, weight: .medium))
    }

    private func compactFooter(_ model: SummitWidgetModel) -> some View {
        VStack(alignment: .leading, spacing: DroppySpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: DroppySpacing.xsm) {
                Text(verbatim: model.percentText)
                    .font(.system(size: 22, weight: .bold))
                    .monospacedDigit()
                Text(model.state == .notLogging ? "not logging" : "of the way up")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
            }
            HStack(spacing: DroppySpacing.xsm) {
                TomatoGlyph()
                Text(verbatim: "\(model.todayTomatoes) today")
                    .monospacedDigit()
                Spacer(minLength: DroppySpacing.sm)
                JarGlyph()
                Text(verbatim: "\(model.todayJars)")
                    .monospacedDigit()
            }
            .font(.system(size: 11, weight: .medium))
        }
    }
}

/// A tomato, for the footers.
struct TomatoGlyph: View {
    var size: CGFloat = 11

    var body: some View {
        ZStack(alignment: .top) {
            Circle()
                .fill(SummitInk.tomato)
                .frame(width: size, height: size)
            Capsule()
                .fill(SummitInk.leaf)
                .frame(width: size * 0.45, height: size * 0.28)
                .offset(y: -size * 0.12)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A jar of four tomatoes, for the footers.
struct JarGlyph: View {
    var size: CGFloat = 11

    var body: some View {
        VStack(spacing: size * 0.06) {
            RoundedRectangle(cornerRadius: size * 0.1, style: .continuous)
                .fill(SummitInk.lid)
                .frame(width: size * 0.62, height: size * 0.18)
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                .fill(SummitInk.tomato)
                .frame(width: size * 0.72, height: size * 0.76)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
