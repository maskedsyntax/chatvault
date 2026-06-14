import Foundation

public enum ParserWarning: Equatable, Sendable {
    case unparseableLine(String, Int)
}
