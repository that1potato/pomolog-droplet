//
//  HostProbe.swift
//  Pomodorolog
//
//  Stage 1 of the summit work, removed before release. A widget with two
//  buttons, a takeover, and test HUDs when a focus reaches zero and when a
//  session is logged. Each attempt goes to diagnostics.log with the host's
//  answer, to learn what Droppy allows while its own Pomodoro holds the notch.
//

import DroppyKit
import SwiftUI

// MARK: - Widget

extension PomodorologDroplet: ShelfWidgetProviding {
    static let probeWidgetID: ShelfWidgetID = "probe"

    public var widgetDescriptors: [ShelfWidgetDescriptor] {
        [
            ShelfWidgetDescriptor(
                id: Self.probeWidgetID,
                title: "Pomolog probe",
                systemImage: "testtube.2",
                layoutTraits: ShelfWidgetLayoutTraits(
                    preferredSoloWidth: 420,
                    preferredPairedWidth: 210,
                    contentHeight: .fixed(96)
                ),
                searchKeywords: ["pomolog", "probe"]
            )
        ]
    }

    public func makeWidgetView(_ id: ShelfWidgetID, context: ShelfWidgetContext) -> AnyView {
        AnyView(ProbeWidget(droplet: self, context: context))
    }
}

private struct ProbeWidget: View {
    @ObservedObject var droplet: PomodorologDroplet
    let context: ShelfWidgetContext

    var body: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.sm) {
            HStack(spacing: DroppySpacing.xsm) {
                Image(systemName: "testtube.2")
                    .font(.system(size: 12, weight: .medium))
                Text("Pomolog probe")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
            HStack(spacing: DroppySpacing.sm) {
                Button(context.isCompact ? "HUD" : "Show HUD") { droplet.probeShowHUD() }
                    .buttonStyle(DroppyQuietButtonStyle(size: .small))
                Button(context.isCompact ? "Takeover" : "Open takeover") { droplet.probeOpenTakeover() }
                    .buttonStyle(DroppyQuietButtonStyle(size: .small))
            }
            Text(verbatim: droplet.probeStatus)
                .font(.system(size: 11))
                .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                .lineLimit(1)
        }
        .padding(context.contentInsets)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Takeover

/// How Droppy finds the takeover: it casts the droplet to
/// `ExpandedSurfaceHosting` and reads the provider. Conforming to
/// `ExpandedSurfaceProviding` alone renders in the harness, but Droppy refuses
/// every presentation.
extension PomodorologDroplet: ExpandedSurfaceHosting {
    public var expandedSurfaceProvider: (any ExpandedSurfaceProviding)? { self }
}

extension PomodorologDroplet: ExpandedSurfaceProviding {
    static let probeSurfaceID: ExpandedSurfaceID = "probe-takeover"

    public var expandedSurfaces: [ExpandedSurfaceDescriptor] {
        [
            ExpandedSurfaceDescriptor(
                id: Self.probeSurfaceID,
                title: "Pomolog probe",
                systemImage: "testtube.2",
                suppresses: [.shelfWidgets]
            )
        ]
    }

    public func makeExpandedSurfaceView(_ id: ExpandedSurfaceID, context: ExpandedSurfaceContext) -> AnyView {
        AnyView(ProbeTakeover(droplet: self, size: context.availableSize))
    }

    public func expandedSurfaceSize(_ id: ExpandedSurfaceID, fitting proposal: ExpandedSurfaceSizeProposal) -> CGSize? {
        diagnose("probe: takeover size asked, standard \(Int(proposal.standardSize.width))×\(Int(proposal.standardSize.height)), maximum \(Int(proposal.maximumSize.width))×\(Int(proposal.maximumSize.height))")
        return CGSize(
            width: min(640, proposal.maximumSize.width),
            height: min(330, proposal.maximumSize.height)
        )
    }

    public func expandedSurfaceDidDismiss(
        _ id: ExpandedSurfaceID,
        presentation: ExpandedSurfacePresentation,
        reason: ExpandedSurfaceDismissalReason
    ) {
        diagnose("probe: takeover dismissed (\(reason))")
    }
}

private struct ProbeTakeover: View {
    @ObservedObject var droplet: PomodorologDroplet
    let size: CGSize

    var body: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.md) {
            HStack(spacing: DroppySpacing.xsm) {
                Image(systemName: "testtube.2")
                    .font(.system(size: 12, weight: .medium))
                Text("Pomolog probe")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                Button {
                    droplet.probeCloseTakeover()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(DroppyCircleButtonStyle(size: 24))
                .accessibilityLabel("Close")
            }
            Text("The takeover opened.")
                .font(.system(size: 20, weight: .semibold))
            Text(verbatim: "It's \(Int(size.width)) × \(Int(size.height)) points. The expedition log would go here.")
                .font(.system(size: 13))
                .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
            Spacer(minLength: 0)
        }
        .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
        .padding(DroppySpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            droplet.diagnose("probe: takeover appeared at \(Int(size.width))×\(Int(size.height))")
        }
    }
}

// MARK: - HUDs

extension PomodorologDroplet: HUDPresenting {}

extension PomodorologDroplet {
    /// What Droppy granted, written once at activation.
    func probeReportGrants() {
        guard let host else { return }
        let granted = host.grantedCapabilities.map(\.rawValue).sorted()
        diagnose("probe: granted \(granted.isEmpty ? "nothing" : granted.joined(separator: ", ")); hud \(host.isGranted(.hud)), expanded-surface \(host.isGranted(.expandedSurface))")
    }

    /// The widget's Show HUD button: a card now, from inside the open shelf,
    /// and another 5 seconds later, once the shelf has had time to close.
    func probeShowHUD() {
        let shown = presentProbeHUD(
            id: "probe.manual", symbol: "testtube.2", strip: "Probe",
            card: true, title: "A HUD from Pomolog", detail: "Pressed on the probe widget."
        )
        probeStatus = "HUD \(shown ? "accepted" : "refused") at \(Self.probeClock()), again in 5 s"
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self else { return }
            let later = self.presentProbeHUD(
                id: "probe.delayed", symbol: "testtube.2", strip: "Probe, 5 s later",
                card: true, title: "A HUD from Pomolog", detail: "Sent 5 seconds after the button."
            )
            self.probeStatus = "Delayed HUD \(later ? "accepted" : "refused") at \(Self.probeClock())"
        }
    }

    /// The widget's Open takeover button: now, and once more 5 seconds later
    /// if Droppy refused it, with the shelf closed by then.
    func probeOpenTakeover() {
        let shown = presentProbeTakeover(when: "from the open shelf", opensShelf: false)
        probeStatus = "Takeover \(shown ? "presented" : "refused") at \(Self.probeClock())\(shown ? "" : ", again in 5 s")"
        guard !shown else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self else { return }
            let later = self.presentProbeTakeover(when: "5 s later", opensShelf: true)
            self.probeStatus = "Delayed takeover \(later ? "presented" : "refused") at \(Self.probeClock())"
        }
    }

    @discardableResult
    private func presentProbeTakeover(when: String, opensShelf: Bool) -> Bool {
        guard let host else { return false }
        let presentation = host.notchSurface.presentExpandedSurface(
            ExpandedSurfacePresentationRequest(surfaceID: Self.probeSurfaceID, opensShelf: opensShelf)
        )
        let shown = presentation != nil
        diagnose("probe: takeover \(shown ? "presented" : "refused") \(when), opensShelf \(opensShelf); granted \(host.isGranted(.expandedSurface)), shelf-write \(host.isGranted(.shelfWrite)), shelf expanded \(host.shelf.isExpanded)")
        return shown
    }

    func probeCloseTakeover() {
        host?.notchSurface.dismissExpandedSurface(Self.probeSurfaceID)
    }

    /// A strip the moment a focus reaches zero, while Droppy shows its own
    /// time-up in the notch.
    func probeZero(_ session: ActiveSession) {
        presentProbeHUD(
            id: "probe.zero", symbol: "flag.checkered", strip: "Zero: \(session.sectionName)",
            card: false, title: "", detail: ""
        )
    }

    /// A card the moment a session is logged, usually as Droppy moves on to
    /// the next section, with Droppy's success cue.
    func probeLogged(_ record: SessionRecord) {
        guard record.kind != .clock else { return }
        presentProbeHUD(
            id: "probe.logged", symbol: "checkmark.circle", strip: "Logged",
            card: true, title: "Logged \(record.sectionName)",
            detail: "\(TimerFormat.duration(seconds: record.activeSeconds)), \(record.outcome.rawValue), ended by \(record.endedBy.rawValue)"
        )
        host?.feedback.play(.success)
        diagnose("probe: played the success cue")
    }

    @discardableResult
    private func presentProbeHUD(id: String, symbol: String, strip: String, card: Bool, title: String, detail: String) -> Bool {
        guard let host else { return false }
        let running = session.map { "\($0.sectionName) running" } ?? "nothing running"
        let request: DropletHUDRequest
        if card {
            request = DropletHUDRequest(
                id: id,
                duration: 4,
                priority: .normal,
                accessibilityLabel: "Pomolog probe. \(title)",
                isExpanded: true,
                expandedContentHeight: 64
            ) {
                ProbeStrip(symbol: symbol, text: strip)
            } expanded: {
                VStack(alignment: .leading, spacing: DroppySpacing.xs) {
                    Text("Pomolog probe")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                    Text(verbatim: title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    Text(verbatim: detail)
                        .font(.system(size: 12))
                        .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            request = DropletHUDRequest(id: id, duration: 3, accessibilityLabel: "Pomolog probe. \(strip)") {
                ProbeStrip(symbol: symbol, text: strip)
            }
        }
        let shown = host.hud.present(request)
        diagnose("probe: HUD \(id) \(card ? "card" : "strip") \(shown ? "accepted" : "refused"), \(running); shelf expanded \(host.shelf.isExpanded), granted \(host.isGranted(.hud))")
        return shown
    }

    private static func probeClock() -> String {
        Date().formatted(Date.FormatStyle().hour().minute().second())
    }
}

/// A strip's content at its two outer edges, nothing over the camera housing.
private struct ProbeStrip: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: DroppyLiveActivityMetrics.iconSize, weight: .semibold))
            Spacer(minLength: 0)
            Text(verbatim: text)
                .font(.system(size: DroppyLiveActivityMetrics.labelFontSize, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
    }
}
