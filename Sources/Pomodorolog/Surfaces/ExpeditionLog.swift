//
//  ExpeditionLog.swift
//  Pomodorolog
//
//  The expedition log: a takeover on the shelf, opened from the summit
//  widget. Stage 4 fills it; for now it says so.
//

import DroppyKit
import SwiftUI

/// How Droppy finds the takeover: it casts the droplet to
/// `ExpandedSurfaceHosting` and reads the provider. Conforming to
/// `ExpandedSurfaceProviding` alone renders in the harness, but Droppy refuses
/// every presentation (LIMITATIONS.md).
extension PomodorologDroplet: ExpandedSurfaceHosting {
    public var expandedSurfaceProvider: (any ExpandedSurfaceProviding)? { self }
}

extension PomodorologDroplet: ExpandedSurfaceProviding {
    static let expeditionLogID: ExpandedSurfaceID = "log"

    public var expandedSurfaces: [ExpandedSurfaceDescriptor] {
        [
            ExpandedSurfaceDescriptor(
                id: Self.expeditionLogID,
                title: "Expedition log",
                systemImage: "mountain.2.fill",
                suppresses: [.shelfWidgets]
            )
        ]
    }

    public func makeExpandedSurfaceView(_ id: ExpandedSurfaceID, context: ExpandedSurfaceContext) -> AnyView {
        AnyView(ExpeditionLogView(droplet: self))
    }

    public func expandedSurfaceSize(_ id: ExpandedSurfaceID, fitting proposal: ExpandedSurfaceSizeProposal) -> CGSize? {
        CGSize(width: min(640, proposal.maximumSize.width), height: min(330, proposal.maximumSize.height))
    }

    func openExpeditionLog() {
        guard let host else { return }
        let shown = host.notchSurface.presentExpandedSurface(
            ExpandedSurfacePresentationRequest(surfaceID: Self.expeditionLogID, opensShelf: true)
        ) != nil
        if !shown { diagnose("the expedition log was refused") }
    }

    func closeExpeditionLog() {
        host?.notchSurface.dismissExpandedSurface(Self.expeditionLogID)
    }
}

private struct ExpeditionLogView: View {
    @ObservedObject var droplet: PomodorologDroplet

    var body: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.md) {
            HStack(spacing: DroppySpacing.xsm) {
                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 12, weight: .medium))
                Text("Expedition log")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                Button {
                    droplet.closeExpeditionLog()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(DroppyCircleButtonStyle(size: 24))
                .accessibilityLabel("Close")
            }
            Text("The expedition log comes in the next stage.")
                .font(.system(size: 13))
                .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
            Spacer(minLength: 0)
        }
        .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
        .padding(DroppySpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
