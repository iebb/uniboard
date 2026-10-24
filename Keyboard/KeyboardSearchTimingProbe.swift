#if DEBUG
import Foundation
import SwiftUI
#if canImport(Darwin)
import Darwin
#endif

/// DEBUG builds only: how long the keyboard's last catalog search took,
/// whether the shared search index served it, and the extension's memory
/// footprint, so the search benchmark UI test can read them from the
/// keyboard process. Holds no query text.
enum KeyboardSearchTiming {
    static func describe(serial: Int, milliseconds: Double, indexed: Bool, results: Int) -> String {
        String(format: "n=%d ms=%.1f indexed=%d results=%d footprintMB=%.1f",
               serial, milliseconds, indexed ? 1 : 0, results, footprintMB())
    }

    /// The physical footprint jetsam limits a keyboard extension by.
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }
}

/// A 1-point, transparent element the UI test reads by identifier.
struct KeyboardSearchTimingProbe: View {
    let timing: String
    var body: some View {
        Text(timing.isEmpty ? "none" : timing)
            .font(.system(size: 1))
            .foregroundStyle(.clear)
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .accessibilityLabel(timing.isEmpty ? "none" : timing)
            .accessibilityIdentifier("keyboard.search.timing")
    }
}
#endif
