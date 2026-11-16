//
//  SVGPath.swift
//  Pomodorolog
//
//  Path data in SVG's notation, turned into a SwiftUI Path, so artwork drawn
//  and approved as SVG moves over number for number. Only the commands that
//  artwork uses: absolute M, L, C, Q and Z.
//

import SwiftUI

enum SVGPath {
    private enum Token {
        case command(Character)
        case number(CGFloat)
    }

    /// The path `data` describes, or an empty path when it holds a command
    /// other than M, L, C, Q and Z, or a command short of numbers.
    static func path(_ data: String) -> Path {
        let tokens = tokenize(data)
        var path = Path()
        var index = 0
        var command: Character = "M"

        func number() -> CGFloat? {
            guard index < tokens.count, case .number(let value) = tokens[index] else { return nil }
            index += 1
            return value
        }
        func point() -> CGPoint? {
            guard let x = number(), let y = number() else { return nil }
            return CGPoint(x: x, y: y)
        }

        while index < tokens.count {
            if case .command(let next) = tokens[index] {
                command = next
                index += 1
            }
            switch command {
            case "M":
                guard let to = point() else { return Path() }
                path.move(to: to)
                // Further pairs after a move are lines, as in SVG.
                command = "L"
            case "L":
                guard let to = point() else { return Path() }
                path.addLine(to: to)
            case "C":
                guard let control1 = point(), let control2 = point(), let to = point() else { return Path() }
                path.addCurve(to: to, control1: control1, control2: control2)
            case "Q":
                guard let control = point(), let to = point() else { return Path() }
                path.addQuadCurve(to: to, control: control)
            case "Z", "z":
                path.closeSubpath()
                // A close takes no numbers; one here would loop forever.
                if index < tokens.count, case .number = tokens[index] { return Path() }
            default:
                return Path()
            }
        }
        return path
    }

    private static func tokenize(_ data: String) -> [Token] {
        var tokens: [Token] = []
        var number = ""
        func flush() {
            if let value = Double(number) { tokens.append(.number(CGFloat(value))) }
            number = ""
        }
        for character in data {
            if character.isLetter {
                flush()
                tokens.append(.command(character))
            } else if character == "," || character.isWhitespace {
                flush()
            } else if character == "-" {
                // A minus always starts a new number.
                flush()
                number.append(character)
            } else {
                number.append(character)
            }
        }
        flush()
        return tokens
    }
}
