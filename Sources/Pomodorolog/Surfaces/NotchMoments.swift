//
//  NotchMoments.swift
//  Pomodorolog
//
//  What a newly logged session earned, shown in the notch: a strip when a jar
//  fills, a card for a summit and for a sticker. Droppy refuses a HUD while
//  the shelf is open, so a moment waits for it to close (LIMITATIONS.md).
//

import AppKit
import DroppyKit
import SwiftUI

/// Something earned, as it shows in the notch. Worked out when the session is
/// logged, so a moment held until the shelf closes still says what it said
/// then.
enum NotchMoment: Equatable, Sendable {
    /// A day's tomatoes filled another jar.
    case jar(today: Int, week: Int)
    /// A summit, a sticker, or the first run's stickers.
    case card(NotchCard)

    var hudID: String {
        switch self {
        case .jar: "pomolog.jar"
        case .card(let card): card.hudID
        }
    }

    /// Seconds it stays up.
    var duration: TimeInterval {
        switch self {
        case .jar: 4
        case .card: 8
        }
    }
}

/// A card that grows out of the notch: a tile, what happened, and a button to
/// where it can be seen.
struct NotchCard: Equatable, Sendable {
    enum Kind: String, Sendable {
        case summit, sticker, welcome
    }

    enum Action: Equatable, Sendable {
        /// Opens the expedition log.
        case expeditionLog
    }

    let kind: Kind
    let symbol: String
    let tileHex: String
    let title: String
    let detail: String
    let action: Action
    /// A peak's own sticker: its tile draws the peak's symbol.
    var peak: Int? = nil

    var hudID: String { "pomolog.\(kind.rawValue)" }

    var buttonTitle: String {
        switch action {
        case .expeditionLog: "Expedition log"
        }
    }

    /// The word on the strip the card grows out of.
    var stripText: String {
        switch kind {
        case .summit: "Summit"
        case .sticker: "Sticker"
        case .welcome: "Stickers"
        }
    }
}

/// Builds the moments. Plain functions of the rewards, so the wording can be
/// tested.
enum NotchMoments {
    /// What a newly logged session earned: each summit, then the new stickers
    /// as one card, then the jar. Stickers already announced are left out.
    static func make(from events: [RewardEvent], rewards: RewardsSnapshot, announced: Set<String>) -> [NotchMoment] {
        var summits: [NotchMoment] = []
        var stickers: [EarnedSticker] = []
        var jar: NotchMoment?
        for event in events {
            switch event {
            case .summit(let summit):
                summits.append(.card(summitCard(summit)))
            case .sticker(let earned):
                if !announced.contains(earned.sticker.id) { stickers.append(earned) }
            case .jarFilled(_, let jarsThatDay, let jarsThatWeek):
                jar = .jar(today: jarsThatDay, week: jarsThatWeek)
            }
        }
        var moments = summits
        if let card = stickerCard(stickers, rewards: rewards) { moments.append(.card(card)) }
        if let jar { moments.append(jar) }
        return moments
    }

    /// `Summit: Mount Fuji`, `3,776 m in 14 sessions over 4 days. Pick your
    /// next climb.`, on the peak's own sticker: two lines on an island's
    /// card. A peak climbed again says how often.
    static func summitCard(_ summit: Summit) -> NotchCard {
        let height = SummitWidgetModel.metres(summit.peak.height)
        let sessions = TimerFormat.count(summit.sessions, "session", "sessions")
        let days = TimerFormat.count(summit.days, "day", "days")
        let again = switch summit.number {
        case 1: ""
        case 2: ", twice"
        default: ", \(summit.number) times"
        }
        let sticker = Stickers.summit(of: summit.peakIndex)
        return NotchCard(
            kind: .summit,
            symbol: "flag.fill",
            tileHex: sticker?.colorHex ?? "#64D2FF",
            title: "Summit: \(summit.peak.name)\(again)",
            detail: "\(height) m in \(sessions) over \(days). Pick your next climb.",
            action: .expeditionLog,
            peak: summit.peakIndex
        )
    }

    /// `Found on the way: Early bird`, `A tomato finished between 5:00 and
    /// 8:00, at 1,129 m on Mont Blanc. 8 of 24 found.` Several at once share
    /// one card. Nil for none.
    static func stickerCard(_ stickers: [EarnedSticker], rewards: RewardsSnapshot) -> NotchCard? {
        guard let first = stickers.first else { return nil }
        let place = whereFound(first, climb: rewards.climb).map { ", \($0)" } ?? ""
        let found = "\(rewards.stickers.count) of \(Stickers.all.count) found."
        if stickers.count == 1 {
            return NotchCard(
                kind: .sticker,
                symbol: first.sticker.symbol,
                tileHex: first.sticker.colorHex,
                title: "Found on the way: \(first.sticker.name)",
                detail: "\(withoutFullStop(first.sticker.rule))\(place). \(found)",
                action: .expeditionLog,
                peak: first.sticker.peak
            )
        }
        return NotchCard(
            kind: .sticker,
            symbol: first.sticker.symbol,
            tileHex: first.sticker.colorHex,
            title: "Found on the way: \(stickers.count) stickers",
            detail: "\(list(stickers.map(\.sticker.name)))\(place). \(found)",
            action: .expeditionLog,
            peak: first.sticker.peak
        )
    }

    /// The first time 2.1 runs: the stickers the log already holds, in one
    /// card rather than one by one. Nil when it holds none.
    static func welcomeCard(rewards: RewardsSnapshot) -> NotchCard? {
        guard let latest = rewards.stickers.last else { return nil }
        let count = rewards.stickers.count
        let left = Stickers.all.count - count
        return NotchCard(
            kind: .welcome,
            symbol: latest.sticker.symbol,
            tileHex: latest.sticker.colorHex,
            title: count == 1 ? "A sticker from your log so far" : "\(count) stickers from your log so far",
            detail: "Found in the sessions you'd already logged. \(left == 0 ? "That's all of them." : "\(left) more to find on the way up.")",
            action: .expeditionLog,
            peak: latest.sticker.peak
        )
    }

    /// The summit, a sticker and a jar with the sample week's numbers, for
    /// Settings' Preview and the harness.
    static func samples(today: String, utcOffsetSeconds: Int) -> [NotchMoment] {
        let records = SampleLog.week(endingOn: today, utcOffsetSeconds: utcOffsetSeconds)
        let sample = RewardsSnapshot(records: records, picks: SampleLog.picks(for: records), today: today)
        var moments: [NotchMoment] = []
        if let summit = sample.climb.summits.last {
            moments.append(.card(summitCard(summit)))
        }
        if let sticker = sample.stickers.first(where: { $0.sticker.id == Stickers.earlyBird.id }) ?? sample.stickers.last,
           let card = stickerCard([sticker], rewards: sample) {
            moments.append(.card(card))
        }
        moments.append(.jar(today: max(1, sample.todayPantry.jars), week: max(1, sample.pantry.jars(inWeekOf: today))))
        return moments
    }

    /// `at 1,129 m on Mont Blanc`: where the climb stood after the session
    /// that earned it. Nil when it climbed nothing, with no climb picked.
    static func whereFound(_ earned: EarnedSticker, climb: Climb) -> String? {
        guard let step = climb.steps.first(where: { $0.recordID == earned.recordID }),
              let peak = step.peakIndex else { return nil }
        return "at \(SummitWidgetModel.metres(step.after)) m on \(Peaks.all[peak].name)"
    }

    /// `Early bird and Unbroken`, `Early bird, Unbroken and Named it`.
    static func list(_ names: [String]) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
    }

    private static func withoutFullStop(_ text: String) -> String {
        text.hasSuffix(".") ? String(text.dropLast()) : text
    }
}

/// A moment waiting to be shown, and how many times Droppy has refused it.
struct PendingMoment: Sendable {
    let moment: NotchMoment
    var attempts = 0
}

extension PomodorologDroplet {
    static let announcedStickersKey = "announcedStickers"
    /// Tries before a moment Droppy keeps refusing is dropped.
    static let momentAttempts = 3

    /// Sticker ids already shown, so each sticker is announced once.
    var announcedStickers: Set<String> {
        get { Set(host?.preferences.value(forKey: Self.announcedStickersKey, as: [String].self) ?? []) }
        set { host?.preferences.setValue(newValue.sorted(), forKey: Self.announcedStickersKey) }
    }

    /// Queues what the session just logged earned.
    func celebrate(since before: RewardsSnapshot) {
        let events = RewardEvents.between(old: before, new: rewards)
        guard !events.isEmpty else { return }
        var announced = announcedStickers
        let moments = NotchMoments.make(from: events, rewards: rewards, announced: announced)
        for case .sticker(let earned) in events {
            announced.insert(earned.sticker.id)
        }
        announcedStickers = announced
        enqueue(moments)
    }

    /// The first time 2.1 runs, one card for the stickers the log already
    /// holds. Every sticker after it gets its own moment.
    func welcomeIfFirstRun() {
        guard let host, !host.preferences.hasValue(forKey: Self.announcedStickersKey) else { return }
        announcedStickers = Set(rewards.stickers.map(\.sticker.id))
        guard let card = NotchMoments.welcomeCard(rewards: rewards) else { return }
        pendingMoments.append(PendingMoment(moment: .card(card)))
        // Once Droppy has settled after launching, not during it.
        waitForNextMoment(4)
    }

    /// Settings' Preview: the three moments with the sample week's numbers.
    func previewMoments() {
        enqueue(NotchMoments.samples(today: today, utcOffsetSeconds: TimeZone.current.secondsFromGMT()))
    }

    /// The harness has no Droppy Pomodoro to earn anything, so it holds a
    /// sample moment up for the HUD shot: the summit card, or the one
    /// `--pomolog-moment sticker`, `jar` or `welcome` names.
    func presentHarnessMoment() {
        let arguments = ProcessInfo.processInfo.arguments
        let named = arguments.firstIndex(of: "--pomolog-moment").flatMap { index in
            arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
        } ?? NotchCard.Kind.summit.rawValue
        let moment: NotchMoment?
        if named == NotchCard.Kind.welcome.rawValue {
            moment = NotchMoments.welcomeCard(rewards: rewards).map { .card($0) }
        } else {
            moment = NotchMoments.samples(today: today, utcOffsetSeconds: TimeZone.current.secondsFromGMT())
                .first { $0.hudID == "pomolog.\(named)" }
        }
        if let moment { present(moment, holdsUp: true) }
    }

    func enqueue(_ moments: [NotchMoment]) {
        guard !moments.isEmpty else { return }
        pendingMoments.append(contentsOf: moments.map { PendingMoment(moment: $0) })
        showNextMoment()
    }

    /// Shows the next moment unless one is up. While the shelf is open it
    /// looks again every couple of seconds: Droppy refuses a HUD over the
    /// shelf.
    func showNextMoment() {
        guard momentTask == nil, let host, !pendingMoments.isEmpty else { return }
        if host.shelf.isExpanded {
            waitForNextMoment(2)
            return
        }
        var next = pendingMoments.removeFirst()
        if present(next.moment, holdsUp: false) {
            diagnose("showed \(next.moment.hudID)")
            if case .card(let card) = next.moment, card.kind != .welcome {
                host.feedback.play(.success)
            }
            waitForNextMoment(next.moment.duration + 0.6)
        } else {
            next.attempts += 1
            diagnose("\(next.moment.hudID) was refused, try \(next.attempts) of \(Self.momentAttempts)")
            if next.attempts < Self.momentAttempts { pendingMoments.insert(next, at: 0) }
            waitForNextMoment(4)
        }
    }

    func stopMoments() {
        momentTask?.cancel()
        momentTask = nil
        actionTask?.cancel()
        actionTask = nil
        pendingMoments.removeAll()
    }

    private func waitForNextMoment(_ seconds: TimeInterval) {
        momentTask?.cancel()
        momentTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            self.momentTask = nil
            self.showNextMoment()
        }
    }

    /// Hands a moment to Droppy. `holdsUp` keeps it up until replaced, for
    /// the harness's shot.
    @discardableResult
    private func present(_ moment: NotchMoment, holdsUp: Bool) -> Bool {
        guard let host else { return false }
        let duration: TimeInterval? = holdsUp ? nil : moment.duration
        let geometry = host.environment.notchGeometry
        let housing = geometry.isHardwareNotch ? geometry.closedWidth : 0
        switch moment {
        case .jar(let today, let week):
            return host.hud.present(DropletHUDRequest(
                id: moment.hudID,
                duration: duration,
                priority: .normal,
                accessibilityLabel: "Jar filled: \(today) today, \(week) this week"
            ) {
                JarStrip(today: today, week: week, housing: housing)
            })
        case .card(let card):
            return host.hud.present(DropletHUDRequest(
                id: moment.hudID,
                duration: duration,
                priority: .normal,
                accessibilityLabel: "\(card.title). \(card.detail)",
                isExpanded: true,
                expandedContentHeight: MomentCard.height(for: card),
                content: {
                    CardStrip(card: card, housing: housing)
                },
                expanded: { [weak self] in
                    MomentCard(card: card) { self?.perform(card) }
                }
            ))
        }
    }

    /// The card's button: the HUD goes, then, once its close has settled, the
    /// shelf opens where the card pointed.
    private func perform(_ card: NotchCard) {
        guard let host else { return }
        host.hud.dismiss(id: card.hudID)
        actionTask?.cancel()
        actionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, let self else { return }
            switch card.action {
            case .expeditionLog:
                self.openExpeditionLog()
            }
        }
    }
}

/// A filled jar: the jar and its words at the left edge, the count at the
/// right, nothing over the camera housing.
private struct JarStrip: View {
    let today: Int
    let week: Int
    /// The camera housing's width, 0 on an island.
    let housing: CGFloat

    var body: some View {
        // A notch leaves each side about 44 points, so the words give way to
        // shorter ones there; an island has room for more.
        StripLayout(housing: housing) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DroppySpacing.xsm) {
                    JarGlyph(size: 14)
                    Text("Jar filled")
                }
                JarGlyph(size: 14)
            }
        } trailing: {
            ViewThatFits(in: .horizontal) {
                Text(verbatim: "\(today) today · \(week) this week")
                Text(verbatim: "\(week) this week")
                Text(verbatim: TimerFormat.count(week, "jar", "jars"))
            }
            .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
        }
    }
}

/// The strip a card grows out of: its symbol at the left, a word at the
/// right.
private struct CardStrip: View {
    let card: NotchCard
    let housing: CGFloat

    var body: some View {
        StripLayout(housing: housing) {
            if let peak = card.peak {
                // The peak's own symbol, in its sticker's colour.
                // The symbol is wide and low in its disc: at twice the
                // icon size it stands as tall as the label's capitals.
                SummitGlyph(peak: peak, ink: Color(hex: card.tileHex))
                    .frame(width: DroppyLiveActivityMetrics.iconSize * 2.2, height: DroppyLiveActivityMetrics.iconSize * 2.2)
            } else {
                Image(systemName: card.symbol)
                    .font(.system(size: DroppyLiveActivityMetrics.iconSize, weight: .semibold))
                    .foregroundStyle(Color(hex: card.tileHex))
            }
        } trailing: {
            Text(verbatim: card.stripText)
                .minimumScaleFactor(0.75)
        }
    }
}

/// Content at the two outer edges of a strip, each kept to its side of the
/// camera housing, as Droppy's own caps-lock and Wi-Fi strips are.
private struct StripLayout<Leading: View, Trailing: View>: View {
    let housing: CGFloat
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        GeometryReader { proxy in
            // An island's strip is narrower than any housing and has none.
            let gap = proxy.size.width > housing + 2 * DroppySpacing.xxxl ? housing : 0
            let side = max(0, (proxy.size.width - gap) / 2)
            HStack(spacing: 0) {
                leading
                    .frame(maxWidth: side, alignment: .leading)
                Spacer(minLength: 0)
                trailing
                    .frame(maxWidth: side, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .font(.system(size: DroppyLiveActivityMetrics.labelFontSize, weight: .semibold))
        .lineLimit(1)
        .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
    }
}

/// A summit or a sticker: its tile, what happened, and where to look. One
/// request serves a notch and an island, so the card lays out to the width it
/// is given: on a notch's 344 points the button sits beside the words, on an
/// island's 208 it goes under them.
struct MomentCard: View {
    /// The card's content width on a notch; an island's is 208.
    static let wideWidth: CGFloat = 344
    static let tileSize: CGFloat = 44
    static let narrowTileSize: CGFloat = 28
    /// What the island's layout needs: a line of title, two of detail and the
    /// button.
    static let narrowHeight: CGFloat = 16 + 2 + 30 + 6 + 24 + 2

    let card: NotchCard
    let action: () -> Void

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width >= 300 {
                HStack(spacing: DroppySpacing.md) {
                    tile(Self.tileSize)
                    words(titleLines: 2, detailLines: 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    button
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: DroppySpacing.smd) {
                    tile(Self.narrowTileSize)
                    VStack(alignment: .leading, spacing: DroppySpacing.xsm) {
                        words(titleLines: 1, detailLines: 2)
                        button
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
    }

    private func tile(_ size: CGFloat) -> some View {
        ZStack {
            Circle().fill(Color(hex: card.tileHex))
            if let peak = card.peak {
                SummitGlyph(peak: peak)
            } else {
                Image(systemName: card.symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.78))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func words(titleLines: Int, detailLines: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: card.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                .lineLimit(titleLines)
                .minimumScaleFactor(titleLines == 1 ? 0.85 : 1)
            Text(verbatim: card.detail)
                .font(.system(size: 12))
                .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                .lineLimit(detailLines)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var button: some View {
        Button(card.buttonTitle, action: action)
            .buttonStyle(DroppyQuietButtonStyle(size: .small))
            .fixedSize()
    }

    /// The content height the card asks Droppy for: its words measured at the
    /// width they get on a notch, and never shorter than the island's layout
    /// needs.
    static func height(for card: NotchCard) -> CGFloat {
        let wordsWidth = wideWidth - tileSize - 2 * DroppySpacing.md - buttonWidth(card)
        let words = measure(card.title, .systemFont(ofSize: 13, weight: .semibold), width: wordsWidth)
            + 2
            + measure(card.detail, .systemFont(ofSize: 12), width: wordsWidth)
        return min(140, max(narrowHeight, (max(tileSize, words) + 4).rounded(.up)))
    }

    private static func buttonWidth(_ card: NotchCard) -> CGFloat {
        measureWidth(card.buttonTitle, .systemFont(ofSize: 12, weight: .medium)) + 28
    }

    private static func measure(_ text: String, _ font: NSFont, width: CGFloat) -> CGFloat {
        let rect = NSAttributedString(string: text, attributes: [.font: font]).boundingRect(
            with: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return rect.height.rounded(.up)
    }

    private static func measureWidth(_ text: String, _ font: NSFont) -> CGFloat {
        NSAttributedString(string: text, attributes: [.font: font]).size().width.rounded(.up)
    }
}
