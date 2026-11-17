import Foundation
import SwiftUI
import Testing
@testable import Pomodorolog

@Suite struct SVGPathTests {
    @Test func linesAndACloseMakeABox() {
        let path = SVGPath.path("M0,0 L10,0 L10,5 L0,5 Z")
        #expect(path.cgPath.boundingBoxOfPath == CGRect(x: 0, y: 0, width: 10, height: 5))
    }

    @Test func pairsAfterAMoveAreLines() {
        let path = SVGPath.path("M0,0 10,0 10,10 Z")
        #expect(path.cgPath.boundingBoxOfPath == CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    @Test func curvesAreTracedNotBoxedByTheirControls() {
        let box = SVGPath.path("M2,58 C24,54 34,40 42,18 Q50,10 58,18 Z").cgPath.boundingBoxOfPath
        #expect(box.minX == 2)
        #expect(box.maxY == 58)
        // The quad's apex is halfway to its control, above its ends.
        #expect(abs(box.minY - 14) < 0.01)
    }

    @Test func decimalsAndNegativesParse() {
        let box = SVGPath.path("M-1.5,2.25 L3-4 Z").cgPath.boundingBoxOfPath
        #expect(box.minX == -1.5)
        #expect(box.minY == -4)
        #expect(box.maxY == 2.25)
    }

    @Test func anythingElseGivesNoPath() {
        #expect(SVGPath.path("M0,0 A5,5 0 0 1 10,10").isEmpty)
        #expect(SVGPath.path("M0,0 L10").isEmpty)
        #expect(SVGPath.path("M0,0 L10,0 Z 5").isEmpty)
    }
}

@Suite struct PeakIconTests {
    @Test func everyPeakHasArtAndOnlyOlympusMonsIsOnMars() {
        #expect(PeakArt.all.count == Peaks.all.count)
        #expect(PeakShapes.all.map(\.isMars) == [false, false, false, false, false, false, true])
    }

    @Test func everyPathParsesAndStandsOnTheGroundInsideTheBox() {
        let box = CGRect(origin: .zero, size: PeakArt.box)
        for shapes in PeakShapes.all {
            let outline = shapes.silhouette.cgPath.boundingBoxOfPath
            #expect(!shapes.silhouette.isEmpty)
            #expect(!shapes.shade.isEmpty)
            #expect(box.contains(outline))
            #expect(abs(outline.maxY - PeakArt.ground) < 0.01)
            for extra in [shapes.snow, shapes.front].compactMap({ $0 }) {
                #expect(!extra.isEmpty)
            }
        }
    }

    @Test func everestStandsTallestAndOlympusMonsSitsLowest() {
        let tops = PeakShapes.all.map(\.summitY)
        #expect(tops.min() == tops[5])
        #expect(tops.max() == tops[6])
    }

    @Test func theHatchingAndTheGroundLineStayInsideTheBoxesTheyAreClippedTo() {
        #expect(!PeakShapes.hatch.isEmpty)
        let ground = PeakShapes.groundLine.cgPath.boundingBoxOfPath
        #expect(ground.minX == 0)
        #expect(ground.maxX == PeakArt.box.width)
        #expect(abs(ground.midY - PeakArt.ground) < 1)
    }

    @Test func theFillRisesFromTheGroundToTheTop() {
        let fuji = PeakShapes.all[1]
        #expect(fuji.fillLine(at: 0) == PeakArt.ground)
        #expect(fuji.fillLine(at: 1) == fuji.summitY)
        #expect(abs(fuji.fillLine(at: 0.5) - (fuji.summitY + PeakArt.ground) / 2) < 0.001)
        #expect(fuji.fillLine(at: 2) == fuji.summitY)
        #expect(fuji.fillLine(at: -1) == PeakArt.ground)
    }
}

@Suite struct PaperGrainTests {
    @Test func theGrainIsTheSameEveryTimeAndCentredOnMidGrey() {
        let samples = PaperGrain.samples()
        #expect(samples.count == PaperGrain.side * PaperGrain.side)
        #expect(samples == PaperGrain.samples())
        let values = samples.map { Double($0) / 255 }
        let mean = values.reduce(0, +) / Double(values.count)
        let deviation = (values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)).squareRoot()
        #expect(abs(mean - 0.5) < 0.01)
        #expect(abs(deviation - PaperGrain.spread) < 0.01)
        #expect(PaperGrain.tile != nil)
    }
}
