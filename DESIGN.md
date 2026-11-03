---
version: alpha
name: "zg-gui examples"
description: "Quiet, legible developer examples with visible, editable drawings."
colors:
  primary: "#4351bf"
  background: "#f7f8fa"
  surface: "#ffffff"
  text: "#262b38"
  muted: "#596174"
  border: "#d9deea"
  danger: "#a33948"
typography:
  sans:
    fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif'
  mono:
    fontFamily: 'ui-monospace, "SFMono-Regular", Consolas, monospace'
rounded:
  DEFAULT: "7px"
  lg: "12px"
spacing:
  section-gap: "24px"
  page-max: "1248px"
components:
  button:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.surface}"
  diagram:
    textColor: "{colors.text}"
  connector:
    textColor: "{colors.muted}"
  source-editor:
    textColor: "{colors.text}"
    backgroundColor: "{colors.background}"
  divider:
    backgroundColor: "{colors.border}"
  inline-error:
    textColor: "{colors.danger}"

---

# Example design context

## Overview

The examples are English-language developer tools for inspecting and editing
synthetic UI state on desktop and mobile. No specific national market or business
workflow is assumed. The diagram example's signature is a paired source/drawing
workspace: readable output above editable text, with each diagram independent.
Familiar controls and the established demo identity take precedence over visual
novelty. Avoid decorative metrics, marketing imagery and ornamental motion.

Runtime tokens in `examples/web/demo-shared.css` are canonical. This file mirrors
the relevant light palette and shared control geometry; it generates no CSS.
Diagram styles consume those variables. `diagram-paint.css` supplies matching
light fallbacks for standalone SVG; downloads embed the current theme variables
and the same paint stylesheet. The diagram example adds no theme provider.

## Colors

Use shared surface, ink, muted, line, accent, tint, input, danger and focus tokens.
Light/dark mappings come from the shared stylesheet and `demo-theme.js` preference.
Shapes use accent outlines and tinted fills; connectors use muted ink. Labels
and arrows convey meaning independently of color. Forced colors use system ink
and canvas values. Browser checks exercise both themes.

## Typography

The existing system sans stack owns prose and SVG labels. Technical source uses
the system monospace stack. Use sentence case and visible labels; retain browser
fallbacks for arbitrary source text. Diagram font size is 14px to match layout
measurement. Source is 13px/1.6; body copy is 16px/1.55. Headings use restrained
weight and tighter tracking.

## Layout

Use a 1248px page maximum, 24px gutters/gaps, and two equally weighted diagram
panels. At 850px, stack panels; at 500px, reduce gutters to 16px. Sources and
actions follow their own drawings. Canvas height reserves 360px (300px on narrow
screens), and source editors reserve 176px. Inline error and download-status
space stays reserved. Document scrolling owns the page; editors/canvases own
their overflow. Scrollbars stay visible and receive the diagram stylesheet's
global baseline.

## Elevation & Depth

Separate panels with borders and surface contrast. Avoid shadows and overlays.

## Shapes

Reuse 7px control radii and 12px panel corners. SVG node shapes communicate their
source semantics; preserve the layout engine's geometry.

## Components

Shared navigation, theme controls and focus outlines come from demo-shared.css.
Render/reset/download actions use native buttons with hover, active, disabled,
busy and visible-focus states. Keyboard activation uses native behavior. Native
source textareas have visible labels, syntax errors announced through status
regions, `aria-invalid` and stable descriptive associations. Enter inserts a
newline; rendering is an explicit action. Forms suppress native validation and
navigation. Each source is transient and resets on reload; only theme persists.

A failed source preserves the accepted drawing and editable draft. Each SVG
receives an accessible name and description; its full source remains available
immediately below. Source reset is a reversible example action. Download errors
remain visible in the shared status area. This example has no dialogs, selection
popups, remote search or business CRUD. No motion is added.

## Do's and Don'ts

- Keep source, error and render action adjacent to the drawing they control.
- Keep retained drawing nodes mounted when geometry or labels change.
- Reuse the existing theme and semantic tokens across every example state.
- Keep last accepted output visible when a draft cannot render.
