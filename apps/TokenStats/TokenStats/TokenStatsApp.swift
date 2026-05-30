//
//  TokenStatsApp.swift
//  TokenStats
//
//  Menu-bar-only app (LSUIElement, set in the generated Info.plist — no Dock
//  icon). The label shows each signed-in Coding Agent's primary (5-hour) Usage
//  Window percent — a single percent when only one is available, or compact
//  side-by-side readings (e.g. "C: 24% X: 12%") when both are. Clicking opens
//  the popover anchored to it.
//

import SwiftUI

@main
struct TokenStatsApp: App {
    private let model = UsageModel()

    init() {
        model.start()
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
                .onAppear { model.refreshOnPopoverOpen() }
        } label: {
            // Monochrome icon + per-agent percent — no threshold colors (PRD).
            Image(systemName: "gauge.with.dots.needle.33percent")
            Text(MenuBarSummary.text(for: model.menuBarSummaries))
        }
        .menuBarExtraStyle(.window)
    }
}
