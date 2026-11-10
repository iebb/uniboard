import SwiftUI

extension KeyboardRowAlignment {
    var title: String {
        switch self {
        case .left: return String(localized: "Left")
        case .center: return String(localized: "Center")
        case .right: return String(localized: "Right")
        case .spaced: return String(localized: "Spread")
        }
    }
    var image: String {
        switch self {
        case .left: return "align.horizontal.left"
        case .center: return "align.horizontal.center"
        case .right: return "align.horizontal.right"
        case .spaced: return "distribute.horizontal.center"
        }
    }
    var hint: String {
        switch self {
        case .left: return String(localized: "Aligns to the left edge")
        case .center: return String(localized: "Centers the row")
        case .right: return String(localized: "Aligns to the right edge")
        case .spaced: return String(localized: "Distributes extra space between keys and gaps")
        }
    }
    var segmentID: String { self == .spaced ? "spread" : rawValue }
}

struct RowAlignmentCard: View {
    let row: Int?
    let alignments: [KeyboardRowAlignment]
    var widthLimitExceeded = false
    var selectRow: ((Int?) -> Void)? = nil
    private let widthLimitHint = String(localized: "Shorten rows that exceed the width limit before changing alignment.")
    let apply: (KeyboardRowAlignment) -> Void
    private var value: KeyboardRowAlignment? {
        if let row { return alignments.indices.contains(row) ? alignments[row] : nil }
        guard let first = alignments.first, alignments.allSatisfy({ $0 == first }) else { return nil }
        return first
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(spacing: 8) {
                HStack {
                    if let selectRow {
                        Picker("Rows", selection: Binding<Int?>(get: { row }, set: selectRow)) {
                            Text("All Rows").tag(Int?.none)
                            ForEach(alignments.indices, id: \.self) { index in
                                Text("Row \(index + 1)").tag(Optional(index))
                                    .accessibilityLabel("Select row \(index + 1)")
                                    .accessibilityAddTraits(row == index ? .isSelected : [])
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("arrange.rows")
                    } else if let row { Text("Row \(row + 1)").font(.subheadline.weight(.semibold)) }
                    else { Text("All Rows").font(.subheadline.weight(.semibold)) }
                    Spacer()
                    Text(value?.title ?? String(localized: "Mixed")).font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityIdentifier("arrange.alignment.value")
                }
                Picker(row.map { String(localized: "Alignment for row \($0 + 1)") } ?? String(localized: "Alignment for all rows"),
                       selection: Binding<KeyboardRowAlignment?>(get: { value }, set: { if let value = $0 { apply(value) } })) {
                    ForEach([KeyboardRowAlignment.left, .center, .right, .spaced], id: \.self) { choice in
                        Image(systemName: choice.image).imageScale(.medium).accessibilityLabel(choice.title).accessibilityHint(widthLimitExceeded ? widthLimitHint : choice.hint)
                            .accessibilityIdentifier("arrange.alignment.\(choice.segmentID)")
                            .tag(Optional(choice))
                    }
                }
                .pickerStyle(.segmented)
                .disabled(widthLimitExceeded)
                .accessibilityValue(value?.title ?? String(localized: "Mixed"))
                .accessibilityHint(widthLimitExceeded ? widthLimitHint : "")
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("arrange.alignment")
            if widthLimitExceeded {
                Text(widthLimitHint).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 16)
            } else {
                Text("Choose a row to change its alignment without editing a key.").font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 16)
            }
        }
    }
}

struct EditorRowBand: View {
    let selected: Bool
    let tooWide: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(selected ? Color.accentColor.opacity(0.08) : .clear)
            .overlay { if selected { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 2) } }
            .overlay {
                if tooWide {
                    RoundedRectangle(cornerRadius: 10).strokeBorder(Color(.systemOrange), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
            }
            .padding(-3)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct EditorRowWidthNote: View {
    let rows: [Int]
    var body: some View {
        if !rows.isEmpty {
            Label {
                if rows.count == 1 {
                    Text("Row \(rows[0] + 1) is wider than the current limit of 12 standard-key widths. Its saved arrangement is kept. Move keys or remove gaps to shorten the row.")
                } else {
                    let list = ListFormatter.localizedString(byJoining: rows.map { String($0 + 1) })
                    Text("Rows \(list) are wider than the current limit of 12 standard-key widths. Their saved arrangements are kept. Move keys or remove gaps to shorten them.")
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color(.systemOrange))
            }
            .font(.footnote).foregroundStyle(.secondary)
            .accessibilityIdentifier("arrange.widthWarning")
        }
    }
}
