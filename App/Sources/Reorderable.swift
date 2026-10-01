import MoniMacCore
import SwiftUI

/// What a drag carries. Payloads are prefixed with their kind, so a drop target accepts only its own
/// kind: never text dragged in from another app, and never a sidebar tab dropped on a section.
enum ReorderPayload: String {
    case tab, section

    func payload(_ id: String) -> String { "\(prefix)\(id)" }

    /// The dragged id, or nil when the payload is some other kind.
    func id(in payload: String) -> String? {
        payload.hasPrefix(prefix) ? String(payload.dropFirst(prefix.count)) : nil
    }

    private var prefix: String { "monimac.\(rawValue):" }
}

extension View {
    /// Accepts a dragged item of `kind` and outlines itself while one hovers over it.
    func reorderDropTarget(_ kind: ReorderPayload, cornerRadius: CGFloat, onDrop: @escaping (String) -> Void) -> some View {
        modifier(ReorderDropTarget(kind: kind, cornerRadius: cornerRadius, onDrop: onDrop))
    }
}

private struct ReorderDropTarget: ViewModifier {
    let kind: ReorderPayload
    let cornerRadius: CGFloat
    let onDrop: (String) -> Void
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .dropDestination(for: String.self) { payloads, _ in
                guard let id = payloads.first.flatMap(kind.id(in:)) else { return false }
                onDrop(id)
                return true
            } isTargeted: { isTargeted = $0 }
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: cornerRadius).stroke(Palette.accent, lineWidth: 2)
                }
            }
    }
}

// MARK: Sections

/// One of a window tab's sections. `allCases` is the default order.
protocol WindowSection: RawRepresentable<String>, CaseIterable, Hashable where AllCases == [Self] {
    /// Consecutive half-width sections share a row.
    var width: SectionWidth { get }
}

/// Which tab's section order the sections inside it read and change. The main window sets it.
@MainActor
struct SectionArranger {
    let monitor: Monitor
    let tab: WindowTab

    func order<Section: WindowSection>(_: Section.Type) -> [Section] {
        monitor.sectionOrder(in: tab, defaults: Section.allCases.map { $0.rawValue }).compactMap { Section(rawValue: $0) }
    }

    func move<Section: WindowSection>(_ section: String, onto target: Section) {
        monitor.moveSection(section, onto: target.rawValue, in: tab, defaults: Section.allCases.map { $0.rawValue })
    }
}

extension EnvironmentValues {
    @Entry var sectionArranger: SectionArranger?
}

/// A window tab's sections in the user's order, with half-width sections paired side by side.
/// Hovering a section shows a grip in the margin to its left; dragging the grip onto another section
/// puts it in that section's place. The order persists in Preferences.
struct ReorderableSections<Section: WindowSection, Content: View>: View {
    var columnSpacing: CGFloat = 32
    @ViewBuilder let content: (Section) -> Content
    @Environment(\.sectionArranger) private var arranger

    var body: some View {
        let order = arranger?.order(Section.self) ?? Section.allCases
        VStack(alignment: .leading, spacing: 20) {
            ForEach(SectionLayout.rows(order, width: \.width), id: \.self) { row in
                HStack(alignment: .top, spacing: columnSpacing) {
                    ForEach(row, id: \.self) { section in
                        ReorderableSection(id: section.rawValue) {
                            content(section)
                        } onDrop: { dropped in
                            arranger?.move(dropped, onto: section)
                        }
                    }
                }
            }
        }
    }
}

private struct ReorderableSection<Content: View>: View {
    let id: String
    @ViewBuilder let content: () -> Content
    let onDrop: (String) -> Void
    @State private var isHovering = false
    /// Fits inside the window content's 24 pt padding.
    private static var gutter: CGFloat { 20 }

    var body: some View {
        // The grip sits in the window's margin. The hover area is widened to cover it, then the
        // negative padding gives the margin back, so the section lays out exactly as before.
        content()
            .padding(.leading, Self.gutter)
            .overlay(alignment: .topLeading) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .frame(width: 16, height: 20)
                    .contentShape(Rectangle())
                    .draggable(ReorderPayload.section.payload(id))
                    .help("Drag to move this section")
                    .opacity(isHovering ? 1 : 0)
            }
            .onHover { isHovering = $0 }
            .padding(.leading, -Self.gutter)
            .reorderDropTarget(.section, cornerRadius: 8, onDrop: onDrop)
    }
}
