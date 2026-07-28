//
//  GlassTabBar.swift
//  TokenStats
//
//  The popover's tab switcher: a Liquid Glass bar in the floating-toolbar
//  idiom — one continuous glass capsule containing the text tabs, with a
//  tinted selection puck that slides between them. Built from real Buttons to
//  keep keyboard/VoiceOver behavior. Falls back to a segmented picker before
//  macOS 26, where the glass APIs don't exist.
//

import SwiftUI

/// The two surfaces in the popover: live Usage Windows, and the Token
/// Odometer broken down by Coding Agent, Model and Token Kind.
enum PopoverTab: Hashable {
    case usage
    case tokens
}

struct GlassTabBar: View {
    @Binding var selection: PopoverTab
    @Namespace private var puck
    @State private var hovered: PopoverTab?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if #available(macOS 26.0, *) {
            glassBar
        } else {
            segmentedPicker
        }
    }

    @available(macOS 26.0, *)
    private var glassBar: some View {
        HStack(spacing: 2) {
            segment(.usage, "Usage")
            segment(.tokens, "Tokens")
        }
        .padding(3)
        // The whole bar shares a single glass surface — one floating slab,
        // like the system's floating toolbars, spanning the popover width.
        .glassEffect(.regular, in: Capsule())
    }

    @available(macOS 26.0, *)
    private func segment(_ value: PopoverTab, _ title: String) -> some View {
        let isSelected = selection == value
        return Button {
            // Under Reduce Motion the puck jumps to the new segment instead of
            // morphing across the bar.
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) { selection = value }
        } label: {
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(isSelected ? Color.white : (hovered == value ? Color.primary : Color.secondary))
                .padding(.vertical, 7)
                // Segments share the bar's width equally.
                .frame(maxWidth: .infinity)
                .background {
                    // The selection puck, morphing between segments on change.
                    if isSelected {
                        Capsule()
                            .fill(.tint)
                            .matchedGeometryEffect(id: "selection", in: puck)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { hovered = value } else if hovered == value { hovered = nil }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var segmentedPicker: some View {
        Picker("View", selection: $selection) {
            Text("Usage").tag(PopoverTab.usage)
            Text("Tokens").tag(PopoverTab.tokens)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}
