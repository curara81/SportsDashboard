import Foundation

struct DatedValue: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}
