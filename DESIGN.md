---
name: TokenStats
description: A native instrument panel for coding-agent usage and token flow.
colors:
  instrument-teal-light: "#08866D"
  instrument-teal-dark: "#45D0AD"
  paper-white: "#F9FAFB"
  quiet-surface-light: "#F1F3F5"
  graphite-black: "#17191C"
  graphite-secondary: "#62676F"
  divider-light: "#D9DCE1"
  night-panel: "#202225"
  night-surface: "#2B2E32"
  night-secondary: "#B3B8C0"
  divider-dark: "#464A50"
  input-signal-blue-light: "#216BC7"
  input-signal-blue-dark: "#4A99F0"
  output-flow-green-light: "#177859"
  output-flow-green-dark: "#38AD87"
  cache-write-amber-light: "#9E6B0F"
  cache-write-amber-dark: "#D99E38"
  cache-read-violet-light: "#665C9E"
  cache-read-violet-dark: "#8F85BF"
typography:
  display:
    fontFamily: "Segoe UI Variable Display, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "38px"
    fontWeight: 700
    lineHeight: 1
  headline:
    fontFamily: "-apple-system, BlinkMacSystemFont, Segoe UI Variable Text, Segoe UI, sans-serif"
    fontSize: "16px"
    fontWeight: 600
    lineHeight: 1.25
  title:
    fontFamily: "-apple-system, BlinkMacSystemFont, Segoe UI Variable Text, Segoe UI, sans-serif"
    fontSize: "14px"
    fontWeight: 600
    lineHeight: 1.25
  body:
    fontFamily: "-apple-system, BlinkMacSystemFont, Segoe UI Variable Text, Segoe UI, sans-serif"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.35
  label:
    fontFamily: "-apple-system, BlinkMacSystemFont, Segoe UI Variable Text, Segoe UI, sans-serif"
    fontSize: "10.5px"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "0.04em"
  numeric:
    fontFamily: "-apple-system, BlinkMacSystemFont, Segoe UI Variable Text, Segoe UI, sans-serif"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.2
    fontFeature: "tnum"
rounded:
  hairline: "1px"
  scroll: "3px"
  item: "4px"
  compact: "5px"
  control: "6px"
  menu: "8px"
  card: "10px"
  flyout: "14px"
  pill: "999px"
spacing:
  hairline: "2px"
  control-inset: "3px"
  compact: "4px"
  snug: "6px"
  standard: "8px"
  control-gap: "12px"
  card-inset: "14px"
  surface-inset: "16px"
  section: "24px"
  onboarding: "28px"
components:
  button-primary:
    backgroundColor: "{colors.instrument-teal-light}"
    textColor: "#FFFFFF"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "4px 12px"
    height: "30px"
  button-secondary:
    backgroundColor: "#FFFFFF"
    textColor: "{colors.graphite-black}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "4px 12px"
    height: "30px"
  button-icon:
    backgroundColor: "transparent"
    textColor: "{colors.graphite-black}"
    rounded: "{rounded.control}"
    size: "32px"
  segment-selected:
    backgroundColor: "{colors.instrument-teal-light}"
    textColor: "#FFFFFF"
    typography: "{typography.body}"
    rounded: "{rounded.pill}"
    padding: "7px 10px"
    height: "34px"
  card:
    backgroundColor: "#FFFFFF"
    textColor: "{colors.graphite-black}"
    rounded: "{rounded.card}"
    padding: "{spacing.card-inset}"
  input:
    backgroundColor: "#FFFFFF"
    textColor: "{colors.graphite-black}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "5px 8px"
    height: "32px"
---

# Design System: TokenStats

## Overview

**Creative North Star: "Native Instrument Panel / 原生仪表台"**

TokenStats should feel like a precision readout the operating system happened to ship: compact, restrained, exact, and immediately trustworthy. The interface stays quiet until a value or state needs attention; hierarchy comes from native typography, measured spacing, and clear numeric alignment rather than decorative chrome.

The visual system is adaptive rather than identical across platforms. macOS uses system materials, SF typography, Liquid Glass where the OS provides it, and the user's accent color; Windows uses Segoe UI Variable, explicit light and dark resources, Instrument Teal, and Windows system colors in High Contrast. Both clients preserve the same information hierarchy and data-color semantics without forcing the same shell.

Avoid the density of an enterprise analytics dashboard, the spectacle of a gamified quota meter, and a cross-platform skin that ignores native controls. The app icon's expressive gradient is a brand asset, not permission to turn the working interface into a gradient field.

**Key Characteristics:**

- Native first, with platform-specific materials and controls
- Compact telemetry organized around one glanceable reading
- Restrained neutral surfaces with rare, purposeful accent
- Tabular numerics and redundant non-color status cues
- Structural layering instead of decorative depth

## Colors

The palette is a neutral instrument housing with color reserved for selection, state, and the four Token Kinds.

The machine-readable frontmatter records both Windows light and dark values where the role changes by theme. On macOS, equivalent semantic roles come from system colors; the user's system tint is the selection accent. Windows High Contrast replaces the authored palette with system Window, Highlight, HighlightText, HotTrack, and GrayText colors.

### Primary

- **Instrument Teal — light** (#08866D): Windows selection, primary action, focus, and active-state accent.
- **Instrument Teal — dark** (#45D0AD): the brighter dark-surface counterpart, chosen to retain contrast without becoming luminous decoration.

### Secondary

- **Input Signal Blue** (#216BC7 light / #4A99F0 dark): direct-input labels and proportion segments.
- **Output Flow Green** (#177859 light / #38AD87 dark): output labels and proportion segments.
- **Cache Write Amber** (#9E6B0F light / #D99E38 dark): cache-write labels and proportion segments.
- **Cache Read Violet** (#665C9E light / #8F85BF dark): cache-read labels and the usually dominant proportion segment; it remains the most desaturated of the four.

### Neutral

- **Paper White** (#F9FAFB): Windows flyout housing and light window background.
- **Quiet Surface** (#F1F3F5): segmented-control wells and secondary light surfaces.
- **Graphite Black** (#17191C): primary light-theme text.
- **Graphite Secondary** (#62676F): explanatory copy, metadata, and de-emphasized labels.
- **Divider Gray** (#D9DCE1): light-theme borders, rules, and container outlines.
- **Night Panel** (#202225): dark-theme window housing.
- **Night Surface** (#2B2E32): raised dark cards and controls.
- **Night Secondary** (#B3B8C0): secondary text on dark surfaces.
- **Dark Divider** (#464A50): dark-theme structural border.

### Named Rules

**The Platform Accent Rule.** macOS follows the user's system tint, Windows uses Instrument Teal, and High Contrast uses Windows system colors; never force one accent implementation across every OS.

**The Data Key Rule.** Input Signal Blue, Output Flow Green, Cache Write Amber, and Cache Read Violet always appear in that order and only identify Token Kind data.

**The App Icon Exception Rule.** The teal-blue-graphite gradient and warm needle belong to the app icon; working surfaces remain tonal and restrained.

## Typography

**Display Font:** Segoe UI Variable Display on Windows; the native rounded system face for macOS gauge numerics  
**Body Font:** Segoe UI Variable Text on Windows; SF system text on macOS  
**Label/Mono Font:** the platform system face with tabular or monospaced digits

**Character:** Typography is utilitarian but not sterile. Native faces carry the platform identity, while semibold labels and tabular figures make a small telemetry surface readable without visual noise.

### Hierarchy

- **Display** (700, 38px, 1): Windows Billing-token hero value; Estimated API value stays a smaller secondary reference, never a competing tab.
- **Headline** (600, 16px, 1.25): product title and major flyout heading.
- **Title** (600, 14px, 1.25): settings sections and agent-level group headings.
- **Body** (400, 13px, 1.35): controls, descriptions, and ordinary labels.
- **Label** (600, 10.5px, 0.04em): uppercase table headings and compact Token Kind keys.
- **Numeric** (tabular figures): totals, countdowns, percentages, and model-token cells; keep columns aligned and value changes stable.

### Named Rules

**The Native Voice Rule.** Use the platform system family and semantic sizes; do not introduce a custom display font into the utility chrome.

**The Figure-First Rule.** In a data row, the number is the strongest element; labels and metadata step back to secondary color before the figure loses contrast.

## Layout

TokenStats uses a single compact vertical flow rather than a dashboard grid. The header, primary tab switcher, active reading, supporting table or gauges, and footer form one scanning axis. On macOS, the Billing-token reading leads the summary while the smaller API-equivalent currency amount sits unlabeled at the trailing edge of its caption row.

The macOS popover is 332pt wide with 16pt outer padding and 16pt section spacing. Its primary tab bar spans the available width; the Token Odometer table keeps compact 42pt value columns and scrolls only after reaching its measured height cap. The Windows flyout is 424 device-independent pixels wide, capped at 760px high, with a 12px outer shadow margin, 16px surface inset, and 14px housing radius. Its Reporting range menu sits above both the Billing-token summary and Odometer table so its scope is unambiguous; the API estimate appears as secondary text beneath the primary reading. Token Kind columns are 64px each. Both layouts grow with real content and introduce vertical scrolling only when content cannot fit the available work area.

Settings can become roomier without losing the native hierarchy: macOS uses a 210–240pt System Settings-style sidebar and a detail pane with a 462pt minimum; onboarding uses a focused 540 × 600pt window with 28pt content insets. Dense information remains grouped by Coding Agent, then Model, then Token Kind.

Spacing follows observed native rhythms: 2–4px for internal meter detail, 6–8px within controls and labels, 12–16px between functional groups, and 24–28px for onboarding or window-level separation.

## Elevation & Depth

The system uses structural layering. Native material, tonal surface changes, one-pixel borders, and dividers establish most depth; controls and cards are flat at rest.

The Windows flyout is the deliberate exception because it floats above the desktop: its outer housing uses a black shadow with 18px blur, 4px downward depth, and 0.44 opacity. macOS popover and window depth stays under AppKit and SwiftUI system ownership. Cards do not invent secondary shadows inside an already floating surface.

### Shadow Vocabulary

- **Desktop Flyout** (`0 4px 18px rgba(0, 0, 0, 0.44)`): only for the top-level Windows notification-area flyout.
- **Native Window** (system-owned): macOS popovers, menus, sheets, and windows use platform material and shadow behavior.

### Named Rules

**The Structural Layer Rule.** Use tone, border, divider, and native material first; reserve authored shadow for a surface that genuinely floats above the desktop.

## Shapes

The form language is softly machined: compact controls use 5–6px corners, menus and segmented wells use 8px, cards use 10px, and the Windows flyout uses 14px. True state tracks—primary tab pucks, gauge tracks, progress bars, and step indicators—use capsules.

Corners stay continuous on macOS and geometrically consistent on Windows. Small brand and settings icons sit in 20–26px rounded-square tiles with 5–6px corners. Table proportion bars are only 3px high with a 1px rounding, reading as calibrated lines rather than decorative pills.

Borders are one pixel at rest. Focus is visible and structural: Windows uses an inset 1.5px ring or an accent-border shift; macOS relies on native focus treatment.

## Components

Components are quietly tactile and native: their states are clear, their silhouettes are compact, and their styling recedes behind the reading.

### Buttons

- **Shape:** 6px Windows corner radius or the equivalent native macOS control shape; 30px minimum Windows height.
- **Primary:** Instrument Teal with white text on Windows; native prominent tint on macOS; 4px × 12px internal padding.
- **Hover / Focus:** hover and press change tone or opacity without translating the control; keyboard focus remains visibly outlined.
- **Secondary / Ghost:** light cards use a one-pixel Divider Gray border; icon actions use a transparent 32px square with a tonal hover fill.

### Chips

- **Style:** Token Kind toggles pair a 6px color key with an uppercase 10.5px label. Compact range segments sit in an 8px tonal well.
- **State:** selection uses accent color and full-strength text. Disabled Token Kinds stay visible at reduced opacity with their raw value preserved; they never disappear.

### Cards / Containers

- **Corner Style:** 10px cards, 14px top-level Windows flyout.
- **Background:** Paper White or Night Surface against the window housing.
- **Shadow Strategy:** flat inside the app; only the top-level desktop flyout receives authored shadow.
- **Border:** one pixel in the theme's divider color.
- **Internal Padding:** 14px for cards, 16px for the flyout housing.

### Inputs / Fields

- **Style:** 32px minimum height, 6px radius, one-pixel divider border, 5px × 8px padding.
- **Focus:** accent border or native focus ring, with selection using the current platform accent.
- **Error / Disabled:** retain legible text and structure; disabled states reduce emphasis rather than removing the control.

### Navigation

- **Style:** the two primary tabs occupy equal width. macOS 26 uses one Liquid Glass capsule with a tinted sliding puck; earlier macOS uses a large native segmented picker. Windows uses an 8px tonal container with compact native-style segments.
- **Range:** Windows uses one compact Reporting range menu above all Tokens data instead of a second segmented control. The selected range scopes the summary and table together.
- **States:** selected text must remain contrast-safe against the actual accent. macOS uses AppKit's alternate selected-control text color rather than assuming white.
- **Motion:** the macOS puck uses a 0.28-second snappy transition and jumps instantly under Reduce Motion.

### Usage Gauge

- Circular gauges use a visible 16%-opacity track, rounded stroke ends, and either a 270° dial with calibration ticks or a complete ring.
- Healthy, low, and critical readings use green, yellow, and red system roles. Critical status also shows a warning glyph so color is never the only signal.
- The center figure is neutral, rounded, semibold, and tabular; status color belongs to the meter, not the number.

### Token Odometer Table

- Group by Coding Agent, then Model, with the four Token Kind columns fixed in Input / Output / Cache Write / Cache Read order.
- On macOS, show only Coding Agents with nonzero raw usage in the displayed range. When none qualify, replace the empty columns and agent sections with one range-scoped empty state.
- Model values use tabular digits and secondary labels. Structurally unavailable measurements use an em dash rather than a fabricated zero.
- A 3px stacked proportion line sits directly below each model row and doubles as the row rule.

## Do's and Don'ts

### Do:

- **Do** preserve native macOS and Windows materials, controls, focus behavior, and system accessibility settings.
- **Do** give one reading clear visual priority and keep supporting telemetry compact.
- **Do** keep Token Kind hues in the established Input / Output / Cache Write / Cache Read order.
- **Do** pair color with labels, figures, dashes, or warning glyphs.
- **Do** use tabular digits for totals, percentages, countdowns, and aligned token columns.
- **Do** reveal depth through native material, tonal contrast, fine borders, and dividers before adding shadow.

### Don't:

- **Don't** turn the flyout into a dense enterprise analytics dashboard.
- **Don't** gamify usage with spectacle, celebration, or alarmist meter treatments.
- **Don't** force macOS and Windows into an identical cross-platform shell.
- **Don't** reuse Token Kind colors as generic brand accents or decorative chart colors.
- **Don't** use the app icon gradient as a general window or card background.
- **Don't** hide unavailable or disabled data when a dimmed value, dash, or explicit state can preserve the table's meaning.
