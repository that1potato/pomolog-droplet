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
                // Scaled 12/11 from the first design, so the smallest type is
                // 12pt, the size of Droppy's own Pomodoro labels.
                layoutTraits: ShelfWidgetLayoutTraits(
                    preferredSoloWidth: 480,
                    preferredPairedWidth: 238,
                    contentHeight: .fixed(232)
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

    /// `2,529`, the big number of the full widget.
    var climbedText: String { Self.metres(scene.climbed) }

    /// `of 4,808 m · 52% up`, under the big number.
    var ofText: String {
        "of \(Self.metres(scene.peak.height)) m · \(percentText) up"
    }

    /// Today's tomatoes as glyphs: a jar for every four, then the rest. At
    /// most three of each, so a long day still fits the column.
    var todayGlyphs: (jars: Int, loose: Int) {
        (min(todayJars, 3), min(max(todayTomatoes - todayJars * Pantry.tomatoesPerJar, 0), 3))
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
                if context.isCompact {
                    MountainSceneView(scene: model.scene, showsMarkers: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    compactFooter(model)
                } else {
                    // The numbers on the left, the mountain on the right.
                    HStack(alignment: .top, spacing: DroppySpacing.md) {
                        statColumn(model)
                            .frame(width: 175, alignment: .topLeading)
                            .frame(maxHeight: .infinity, alignment: .topLeading)
                        MountainSceneView(scene: model.scene, showsMarkers: true)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }
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
            Button {
                droplet.openExpeditionLog()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(DroppyCircleButtonStyle(size: 24))
            .accessibilityLabel("Open the expedition log")
        }
    }

    /// The full widget's left column: how high you are, today's tomatoes, and
    /// how far there is to go.
    private func statColumn(_ model: SummitWidgetModel) -> some View {
        VStack(alignment: .leading, spacing: DroppySpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: model.climbedText)
                    .font(.system(size: 37, weight: .bold))
                    .monospacedDigit()
                    .tracking(-0.65)
                Text(verbatim: "m")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Text(verbatim: model.ofText)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                .lineLimit(1)
            todayRow(model)
                .padding(.top, DroppySpacing.sm)
            Text(verbatim: model.statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                .lineLimit(2)
                .padding(.top, DroppySpacing.smd)
        }
    }

    @ViewBuilder
    private func todayRow(_ model: SummitWidgetModel) -> some View {
        let glyphs = model.todayGlyphs
        if model.todayTomatoes == 0 {
            Text("No tomatoes yet today")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
        } else {
            HStack(alignment: .bottom, spacing: DroppySpacing.xsm) {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(0..<glyphs.jars, id: \.self) { _ in JarGlyph(size: 14) }
                    ForEach(0..<glyphs.loose, id: \.self) { _ in TomatoGlyph(size: 12) }
                }
                Text("today")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(TimerFormat.count(model.todayTomatoes, "tomato", "tomatoes")) and \(TimerFormat.count(model.todayJars, "jar", "jars")) today")
        }
    }

    private func compactFooter(_ model: SummitWidgetModel) -> some View {
        VStack(alignment: .leading, spacing: DroppySpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: DroppySpacing.xsm) {
                Text(verbatim: model.percentText)
                    .font(.system(size: 24, weight: .bold))
                    .monospacedDigit()
                Text(model.state == .notLogging ? "not logging" : "of the way up")
                    .font(.system(size: 12, weight: .medium))
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
            .font(.system(size: 12, weight: .medium))
        }
    }
}

/// A tomato, for the footers.
struct TomatoGlyph: View {
    var size: CGFloat = 12

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
    var size: CGFloat = 12

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
