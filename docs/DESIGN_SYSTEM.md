# Tempo Design System v2.0

> **Your life doesn't have a snooze button. Neither does this app.**

This document is the single source of truth for every visual element in Tempo. Every color, every pixel, every animation curve, every haptic pulse. If it is not in here, it does not ship. If it contradicts something else, this document wins.

This is not a guideline. It is an order.

---

## Table of Contents

1. [Brand Identity](#1-brand-identity)
2. [Design Token Architecture](#2-design-token-architecture)
3. [Color System](#3-color-system)
4. [Typography](#4-typography)
5. [Spacing System](#5-spacing-system)
6. [Depth & Elevation System](#6-depth--elevation-system)
7. [Iconography](#7-iconography)
8. [Component Library](#8-component-library)
9. [Motion Design Language](#9-motion-design-language)
10. [Micro-Interaction Choreography](#10-micro-interaction-choreography)
11. [Loading State Patterns](#11-loading-state-patterns)
12. [Error State Design Patterns](#12-error-state-design-patterns)
13. [Touch Feedback Specifications](#13-touch-feedback-specifications)
14. [Responsive Breakpoints](#14-responsive-breakpoints)
15. [Layout Grid](#15-layout-grid)
16. [Accessibility](#16-accessibility)
17. [Dark Mode](#17-dark-mode)

---

## 1. Brand Identity

### 1.1 Brand Personality

| Adjective | Explanation |
|-----------|-------------|
| **Relentless** | Tempo never lets you off the hook. Every screen communicates forward momentum. There is no "maybe tomorrow" — there is only now. Visual language is urgent, direct, unapologetic. |
| **Disciplined** | Clean lines, rigid grid, no visual clutter. Every pixel earns its place. The design itself embodies the discipline the app demands from its users. Whitespace is intentional, not empty. |
| **Bold** | High-contrast typography, commanding color choices, oversized score displays. Tempo does not whisper — it barks. Headlines hit hard. Numbers dominate. |
| **Tactical** | Military-grade precision in data presentation. Information is structured like a mission briefing: critical metrics first, context second, noise eliminated. Every dashboard is an ops center. |
| **Earned** | Nothing is given. Achievement badges, XP totals, streak counters — every visual reward reflects real effort. The UI celebrates grind, not participation. Locked states are visible reminders of what you have not done yet. |

### 1.2 Voice & Tone Guidelines

**Core principle**: Tempo speaks like a drill sergeant who actually cares about you — tough love, zero fluff, occasional dark humor.

| Context | Tone | Example |
|---------|------|---------|
| **Dashboard greetings** | Direct, no pleasantries | "0500. Time to earn it." / "Day 47. Don't break now." |
| **Achievement unlocked** | Earned respect, brief | "135kg deadlift PR. Noted." / "7-day streak. That's baseline." |
| **Missed target** | Blunt accountability | "You skipped legs. Your quads noticed." / "2100 calories. Target was 2800. Fix it." |
| **Recovery warnings** | Urgent, tactical | "Recovery at 34%. Train smart or don't train at all." |
| **Study reminders** | No-nonsense | "Exam in 6 days. You've studied 2 hours this week. Do the math." |
| **Empty states** | Challenge-issuing | "Nothing here yet. That's on you." |
| **Error messages** | Brief, solution-first | "Connection failed. Retry or check your signal." |
| **Onboarding** | Commanding but welcoming | "Welcome to Tempo. We don't do easy. Let's set your targets." |
| **Loading states** | Militaristic | "Assembling briefing..." / "Pulling your numbers..." |
| **Streak breaks** | Disappointment, not anger | "Streak broken at 23 days. Restart. Now." |

**Copy rules:**
- Maximum 12 words per notification
- No exclamation marks (confidence does not shout)
- No emojis in primary UI (badges/achievements only)
- Use imperative mood: "Log your meal" not "Would you like to log your meal?"
- Numbers always numeric, never written out: "3 sets" not "three sets"
- Time in 24h format: "0600" not "6:00 AM"
- Abbreviations allowed for units: kg, cal, km, min, hr, reps

### 1.3 Logo Description

**Primary mark**: The word "TEMPO" in custom-modified SF Pro Display Heavy. The "T" is extended vertically — its crossbar aligns with the top of the other letters while its stem drops 20% below the baseline, forming a subtle downward anchor (representing grounding/foundation). The "O" is replaced with a circular progress ring at 75% completion — a permanent visual reminder that you are never done.

**Monogram**: The extended "T" with the progress-ring "O" nested at its base-right, forming a compact mark for small contexts.

**Usage rules:**
- Minimum size: 24pt for wordmark, 16pt for monogram
- Clear space: 1x the height of the "E" on all sides
- Never rotate, stretch, add effects, or recolor outside the approved palette
- On light backgrounds: use `Ink Black` (#0D0D0D)
- On dark backgrounds: use `Bone White` (#F5F2ED)
- Never place on busy/photographic backgrounds without a scrim

### 1.4 App Icon Concept

**Shape**: Standard iOS squircle (no custom masking).

**Design**: Solid `Commander Black` (#0D0D0D) background. Centered is a single bold circular progress ring (stroke weight: 14% of icon width) in `Signal Red` (#E63946) at exactly 270 degrees of completion (75%), leaving a 90-degree gap at the top-right. Inside the ring, the letter "T" in `Bone White` (#F5F2ED), SF Pro Display Heavy, sized to fill 48% of the ring's inner diameter. The "T" stem extends slightly below the ring's inner boundary (4% overshoot) — matching the wordmark treatment.

**No gradients. No gloss. No shadows.** The icon should look like it was stamped from steel.

**Size deliverables:**
- 1024x1024 (App Store)
- 180x180 (@3x iPhone)
- 120x120 (@2x iPhone)
- 167x167 (@2x iPad Pro)
- 152x152 (@2x iPad)
- 76x76 (@1x iPad)

---

## 2. Design Token Architecture

### 2.1 Naming Convention

Every design token follows a strict hierarchical naming pattern. No exceptions.

**Pattern**: `tempo.<category>.<group>.<variant>.<state>`

| Segment | Required | Values | Example |
|---------|----------|--------|---------|
| `tempo` | Always | Namespace prefix | `tempo` |
| `<category>` | Always | `color`, `space`, `radius`, `shadow`, `motion`, `font`, `opacity`, `gradient` | `tempo.color` |
| `<group>` | Always | Semantic group within category | `tempo.color.surface` |
| `<variant>` | Usually | Specific token within group | `tempo.color.surface.card` |
| `<state>` | Optional | `default`, `hover`, `pressed`, `disabled`, `focused`, `error`, `dark` | `tempo.color.surface.card.dark` |

### 2.2 Complete Token Registry

#### Color Tokens (74 tokens)

```
tempo.color.primary.ink                 → #0D0D0D
tempo.color.primary.bone                → #F5F2ED
tempo.color.primary.signal              → #E63946

tempo.color.secondary.steel             → #2D2D2D
tempo.color.secondary.concrete          → #6B7280
tempo.color.secondary.ash               → #9CA3AF

tempo.color.accent.amber                → #F59E0B
tempo.color.accent.electric             → #3B82F6
tempo.color.accent.violet               → #8B5CF6

tempo.color.semantic.success            → #22C55E
tempo.color.semantic.warning            → #F59E0B
tempo.color.semantic.error              → #DC2626
tempo.color.semantic.info               → #3B82F6

tempo.color.recovery.green              → #22C55E
tempo.color.recovery.green.bg           → #F0FDF4
tempo.color.recovery.yellow             → #EAB308
tempo.color.recovery.yellow.bg          → #FEFCE8
tempo.color.recovery.red                → #DC2626
tempo.color.recovery.red.bg             → #FEF2F2

tempo.color.sleep.awake                 → #FF6B6B
tempo.color.sleep.light                 → #74B9FF
tempo.color.sleep.deep                  → #0652DD
tempo.color.sleep.rem                   → #A29BFE

tempo.color.bg.primary                  → #F5F2ED
tempo.color.bg.secondary                → #EDEAE4
tempo.color.bg.tertiary                 → #E5E2DC

tempo.color.surface.card                → #FFFFFF
tempo.color.surface.sheet               → #FFFFFF
tempo.color.surface.elevated            → #FFFFFF
tempo.color.surface.overlay             → #0D0D0D @ 40%

tempo.color.text.primary                → #0D0D0D
tempo.color.text.secondary              → #4B5563
tempo.color.text.tertiary               → #6B7280
tempo.color.text.disabled               → #9CA3AF
tempo.color.text.inverse                → #F5F2ED

tempo.color.border.default              → #E5E7EB
tempo.color.border.focused              → #0D0D0D
tempo.color.border.error                → #DC2626
tempo.color.divider.default             → #E5E7EB
tempo.color.divider.heavy               → #D1D5DB
```

#### Spacing Tokens (10 tokens)

```
tempo.space.2xs                         → 2pt
tempo.space.xs                          → 4pt
tempo.space.sm                          → 8pt
tempo.space.md                          → 12pt
tempo.space.lg                          → 16pt
tempo.space.xl                          → 20pt
tempo.space.2xl                         → 24pt
tempo.space.3xl                         → 32pt
tempo.space.4xl                         → 40pt
tempo.space.5xl                         → 48pt
```

#### Component-Specific Spacing Tokens

```
tempo.space.card.padding                → 16pt
tempo.space.card.padding.compact        → 12pt
tempo.space.card.gap                    → 12pt
tempo.space.button.padding.horizontal   → 24pt
tempo.space.button.padding.vertical     → 14pt
tempo.space.button.padding.horizontal.small → 12pt
tempo.space.button.padding.vertical.small   → 8pt
tempo.space.screen.edge                 → 20pt
tempo.space.screen.edge.compact         → 16pt (iPhone SE)
tempo.space.screen.edge.ipad            → 24pt
tempo.space.section.gap                 → 32pt
tempo.space.section.header.top          → 32pt
tempo.space.section.header.bottom       → 8pt
tempo.space.list.item.vertical          → 12pt
tempo.space.list.item.horizontal        → 16pt
tempo.space.sheet.horizontal            → 20pt
tempo.space.sheet.top                   → 16pt
tempo.space.sheet.bottom                → 34pt
tempo.space.modal.horizontal            → 20pt
tempo.space.modal.top                   → 24pt
tempo.space.input.horizontal            → 12pt
tempo.space.input.vertical              → 12pt
tempo.space.input.label.gap             → 8pt
tempo.space.input.helper.gap            → 4pt
tempo.space.chart.legend.gap            → 16pt
tempo.space.button.stack.vertical       → 12pt
tempo.space.button.stack.horizontal     → 8pt
tempo.space.bottom.safe                 → 48pt
```

#### Corner Radius Tokens

```
tempo.radius.xs                         → 3pt    (heatmap cells)
tempo.radius.sm                         → 6pt    (skeleton rects, segmented inner)
tempo.radius.md                         → 8pt    (segmented control, photo thumbnails)
tempo.radius.lg                         → 10pt   (search bar, ghost button)
tempo.radius.xl                         → 12pt   (text fields, stat cards, icon buttons, exercise cards)
tempo.radius.2xl                        → 14pt   (primary/secondary buttons, toast)
tempo.radius.3xl                        → 16pt   (standard cards, workout cards, prescription cards)
tempo.radius.4xl                        → 20pt   (bottom sheets, modal alerts)
tempo.radius.pill                       → 9999pt (pill badges, used as half-height)
tempo.radius.circle                     → 50%    (FAB, avatars, badge circles)
```

#### Opacity Tokens

```
tempo.opacity.10                        → 0.10
tempo.opacity.15                        → 0.15
tempo.opacity.20                        → 0.20
tempo.opacity.40                        → 0.40
tempo.opacity.50                        → 0.50
tempo.opacity.70                        → 0.70
tempo.opacity.80                        → 0.80
tempo.opacity.disabled                  → 0.40
tempo.opacity.overlay.light             → 0.40
tempo.opacity.overlay.dark              → 0.50
tempo.opacity.pressed.primary           → 0.85
tempo.opacity.pressed.ghost             → 0.08
tempo.opacity.skeleton                  → 1.0
```

#### Motion Tokens

```
tempo.motion.micro.duration             → 100ms
tempo.motion.micro.easing               → ease-out (cubic-bezier(0, 0, 0.58, 1))
tempo.motion.small.duration             → 200ms
tempo.motion.small.easing               → ease-in-out (cubic-bezier(0.42, 0, 0.58, 1))
tempo.motion.medium.duration            → 300ms
tempo.motion.medium.spring.damping      → 0.8
tempo.motion.medium.spring.response     → 0.3
tempo.motion.large.duration             → 500ms
tempo.motion.large.spring.damping       → 0.7
tempo.motion.large.spring.response      → 0.5
tempo.motion.data.duration              → 600-800ms
tempo.motion.data.spring.damping        → 0.8
tempo.motion.data.spring.response       → 0.6
tempo.motion.celebration.duration       → 1000ms   // Standard celebration (Dashboard non-neg completion)
tempo.motion.celebration.major.duration → 2000ms   // Major celebration (Training PR)
tempo.motion.celebration.epic.duration  → 3000ms   // Epic celebration (all-time 1RM, Accountability all-complete)
tempo.motion.celebration.spring.damping → 0.5
tempo.motion.celebration.spring.response→ 0.4
tempo.motion.stagger.card               → 60ms
tempo.motion.stagger.bar                → 50ms
tempo.motion.stagger.dot                → 20ms
tempo.motion.stagger.ring               → 150ms
```

### 2.3 Swift Token Access Pattern

```swift
// All tokens accessed via static nested enums under Color.Tempo, Font.Tempo, etc.
// Xcode Asset Catalog names match token paths: "tempo.color.primary.ink"

Color.Tempo.ink           // → Color("tempo.color.primary.ink")
Color.Tempo.surfaceCard          // → Color("tempo.color.surface.card")
TempoSpacing.cardPadding         // → CGFloat(16)
TempoSpacing.xl                  // → CGFloat(20)
TempoAnimation.springMedium      // → Animation.spring(response: 0.3, dampingFraction: 0.8)
TempoShadow.elevation2Light      // → TempoShadow(color:radius:x:y:)
```

---

## 3. Color System

### 3.1 Primary Colors

#### Ink Black

| Property | Value |
|----------|-------|
| **Token** | `tempo.color.primary.ink` |
| **Hex** | `#0D0D0D` |
| **RGB** | `rgb(13, 13, 13)` |
| **HSL** | `hsl(0, 0%, 5%)` |
| **Opacity 10%** | `rgba(13, 13, 13, 0.10)` — used for subtle pressed states on light backgrounds |
| **Opacity 20%** | `rgba(13, 13, 13, 0.20)` — used for FAB shadow, medium overlays |
| **Opacity 50%** | `rgba(13, 13, 13, 0.50)` — used for heavy scrims |
| **Opacity 80%** | `rgba(13, 13, 13, 0.80)` — used for text over semi-transparent surfaces |

**Contrast ratios (WCAG AAA = 7:1, AA = 4.5:1):**

| Background | Ratio | WCAG Level |
|------------|-------|------------|
| Bone White (#F5F2ED) | 17.4:1 | AAA |
| Card Surface (#FFFFFF) | 19.3:1 | AAA |
| Secondary Bg (#EDEAE4) | 15.8:1 | AAA |
| Tertiary Bg (#E5E2DC) | 14.2:1 | AAA |
| Default Border (#E5E7EB) | 14.7:1 | AAA |
| Signal Red (#E63946) | 3.8:1 | AA large text only |
| Mission Green (#22C55E) | 6.4:1 | AA |
| Command Amber (#F59E0B) | 8.2:1 | AAA |
| Electric Blue (#3B82F6) | 4.7:1 | AA |

**DO:**
- Use as primary text color on all light backgrounds
- Use as dark mode base background (OLED true-black appearance)
- Use as focused input border on light mode
- Use for the Prescription Card / Drill Sergeant elements in both modes

**DO NOT:**
- Never place Ink Black text on Signal Red, Protocol Violet, or any surface below 4.5:1 contrast
- Never use as a border color on dark mode (invisible)
- Never use at less than 80% opacity for readable text

---

#### Bone White

| Property | Value |
|----------|-------|
| **Token** | `tempo.color.primary.bone` |
| **Hex** | `#F5F2ED` |
| **RGB** | `rgb(245, 242, 237)` |
| **HSL** | `hsl(37, 33%, 95%)` |
| **Opacity 10%** | `rgba(245, 242, 237, 0.10)` — used for dark mode pressed states |
| **Opacity 20%** | `rgba(245, 242, 237, 0.20)` — used for text glow on dark hero sections |
| **Opacity 50%** | `rgba(245, 242, 237, 0.50)` — used for ghost watermarks |
| **Opacity 80%** | `rgba(245, 242, 237, 0.80)` — used for partially transparent nav bar text |

**Contrast ratios:**

| Background | Ratio | WCAG Level |
|------------|-------|------------|
| Ink Black (#0D0D0D) | 17.4:1 | AAA |
| Steel Gray (#2D2D2D) | 12.5:1 | AAA |
| Dark Card (#1C1C1E) | 14.1:1 | AAA |
| Dark Sheet (#2C2C2E) | 11.2:1 | AAA |
| Dark Elevated (#3A3A3C) | 8.9:1 | AAA |
| Signal Red (#E63946) | 4.6:1 | AA |
| Signal Red Dark (#FF4D5A) | 3.2:1 | Fails — do not use as body text on red |

**DO:**
- Use as primary background in light mode (warm, avoids clinical sterile white)
- Use as primary text color on all dark surfaces
- Use for logo on dark backgrounds
- Use as inverse text on colored buttons (Signal Red bg)

**DO NOT:**
- Never use on white (#FFFFFF) — insufficient contrast (1.1:1), visually indistinguishable
- Never use as text on Signal Red for body text smaller than 18pt
- Never use as background in dark mode (defeats the purpose)

---

#### Signal Red

| Property | Value |
|----------|-------|
| **Token** | `tempo.color.primary.signal` |
| **Hex** | `#E63946` |
| **RGB** | `rgb(230, 57, 70)` |
| **HSL** | `hsl(356, 78%, 56%)` |
| **Dark mode variant** | `#FF4D5A` / `rgb(255, 77, 90)` / `hsl(356, 100%, 65%)` |
| **Opacity 10%** | `rgba(230, 57, 70, 0.10)` — used for ghost button pressed bg, destructive tint |
| **Opacity 15%** | `rgba(230, 57, 70, 0.15)` — used for Drill Sergeant card shadow glow |
| **Opacity 20%** | `rgba(230, 57, 70, 0.20)` — used for Drill Sergeant alert shadow glow |
| **Opacity 50%** | `rgba(230, 57, 70, 0.50)` — not used (too ambiguous — either commit to full red or use a tint) |
| **Opacity 70%** | `rgba(230, 57, 70, 0.70)` — used for loading state button background |
| **Pressed variant** | `#C1303B` (15% darker) |

**Contrast ratios:**

| Background | Ratio | WCAG Level |
|------------|-------|------------|
| Bone White (#F5F2ED) | 4.6:1 | AA (passes 4.5:1 for normal text) |
| Card Surface (#FFFFFF) | 4.9:1 | AA |
| Ink Black (#0D0D0D) | 3.8:1 | AA large text only |
| Dark Card (#1C1C1E) | 4.2:1 | AA large text only |
| Dark Card with dark variant (#FF4D5A on #1C1C1E) | 4.6:1 | AA |

**DO:**
- Use as primary CTA button background with Bone White text (18pt+ semibold minimum)
- Use for active tab bar icon, active progress rings, training module accent
- Use for urgency indicators and the Drill Sergeant alert border
- Use as left-accent bars on workout cards and prescription cards
- Always use the dark variant (#FF4D5A) in dark mode for better visibility

**DO NOT:**
- Never use as body text smaller than 18pt bold on any background
- Never use Signal Red text on Ink Black — contrast is 3.8:1, fails AA for normal text
- Never use as a large background area (it is an accent, not a surface)
- Never pair with Fail Red (#DC2626) in adjacent elements — too similar, causes confusion

---

### 3.2 Secondary Colors

#### Steel Gray

| Property | Value |
|----------|-------|
| **Token** | `tempo.color.secondary.steel` |
| **Hex** | `#2D2D2D` |
| **RGB** | `rgb(45, 45, 45)` |
| **HSL** | `hsl(0, 0%, 18%)` |
| **Opacity 10%** | `rgba(45, 45, 45, 0.10)` |
| **Opacity 20%** | `rgba(45, 45, 45, 0.20)` |
| **Opacity 50%** | `rgba(45, 45, 45, 0.50)` |
| **Opacity 80%** | `rgba(45, 45, 45, 0.80)` |

**Contrast ratios:**

| Background | Ratio | WCAG Level |
|------------|-------|------------|
| Bone White (#F5F2ED) | 12.5:1 | AAA |
| Card Surface (#FFFFFF) | 13.7:1 | AAA |
| Ink Black (#0D0D0D) | 1.4:1 | Fails — never use on Ink Black |

**DO:**
- Use as secondary surface color in light mode (nav bars, grouped backgrounds)
- Use for dark card backgrounds in dark mode context

**DO NOT:**
- Never place Steel Gray text on Ink Black or any dark surface
- Never use as text color — use Ink Black instead

---

#### Concrete

| Property | Value |
|----------|-------|
| **Token** | `tempo.color.secondary.concrete` |
| **Hex** | `#6B7280` |
| **RGB** | `rgb(107, 114, 128)` |
| **HSL** | `hsl(220, 9%, 46%)` |
| **Opacity 10%** | `rgba(107, 114, 128, 0.10)` |
| **Opacity 20%** | `rgba(107, 114, 128, 0.20)` |
| **Opacity 50%** | `rgba(107, 114, 128, 0.50)` |
| **Opacity 80%** | `rgba(107, 114, 128, 0.80)` |

**Contrast ratios:**

| Background | Ratio | WCAG Level |
|------------|-------|------------|
| Bone White (#F5F2ED) | 4.8:1 | AA |
| Card Surface (#FFFFFF) | 5.2:1 | AA |
| Ink Black (#0D0D0D) | 3.6:1 | AA large text only |

**DO:**
- Use for secondary/placeholder text on light backgrounds
- Use for unselected/default icon states
- Use for metadata, timestamps, helper text

**DO NOT:**
- Never use for body text smaller than 14pt on light backgrounds (4.8:1 is marginal)
- Never use for any text on dark backgrounds (3.6:1 fails normal text AA)

---

#### Ash

| Property | Value |
|----------|-------|
| **Token** | `tempo.color.secondary.ash` |
| **Hex** | `#9CA3AF` |
| **RGB** | `rgb(156, 163, 175)` |
| **HSL** | `hsl(218, 11%, 65%)` |
| **Opacity 10%** | `rgba(156, 163, 175, 0.10)` |
| **Opacity 20%** | `rgba(156, 163, 175, 0.20)` |
| **Opacity 50%** | `rgba(156, 163, 175, 0.50)` |
| **Opacity 80%** | `rgba(156, 163, 175, 0.80)` |

**Contrast ratios:**

| Background | Ratio | WCAG Level |
|------------|-------|------------|
| Bone White (#F5F2ED) | 3.1:1 | Fails AA for normal text — decorative only |
| Card Surface (#FFFFFF) | 3.3:1 | Fails AA for normal text — decorative only |
| Ink Black (#0D0D0D) | 5.6:1 | AA |

**DO:**
- Use for decorative elements only: borders, dividers, inactive icons, disabled text
- Use for disabled text on light mode (exempt from contrast requirements per WCAG)

**DO NOT:**
- Never use as readable text on any light background
- Never use for labels, captions, or any text the user must read on light surfaces

---

### 3.3 Accent Colors

#### Command Amber

| Property | Value |
|----------|-------|
| **Token** | `tempo.color.accent.amber` |
| **Hex** | `#F59E0B` |
| **RGB** | `rgb(245, 158, 11)` |
| **HSL** | `hsl(38, 93%, 50%)` |
| **Dark mode variant** | `#FBBF24` / `rgb(251, 191, 36)` / `hsl(43, 96%, 56%)` |
| **Opacity 10%** | `rgba(245, 158, 11, 0.10)` |
| **Opacity 15%** | `rgba(245, 158, 11, 0.15)` — XP badge background |
| **Opacity 20%** | `rgba(245, 158, 11, 0.20)` |
| **Opacity 50%** | `rgba(245, 158, 11, 0.50)` |
| **Opacity 80%** | `rgba(245, 158, 11, 0.80)` |

**Contrast ratios:**

| Background | Ratio | WCAG Level |
|------------|-------|------------|
| Ink Black (#0D0D0D) | 8.2:1 | AAA |
| Dark Card (#1C1C1E) | 7.3:1 | AAA |
| Bone White (#F5F2ED) | 2.1:1 | Fails — decorative only on light |
| Card Surface (#FFFFFF) | 2.3:1 | Fails — decorative only on light |

**DO:**
- Use for XP indicators, achievement highlights, premium features on dark surfaces
- Use as "DRILL SERGEANT" and "ORDERS" label color (always on Ink Black bg)
- Use for warning states (paired with icon, never text-only on light)
- Always pair with a text label or icon on light backgrounds

**DO NOT:**
- Never use as readable text on Bone White or any light surface (2.1:1)
- Never use as the sole indicator of warning state — always pair with icon + text label

---

#### Electric Blue

| Property | Value |
|----------|-------|
| **Token** | `tempo.color.accent.electric` |
| **Hex** | `#3B82F6` |
| **RGB** | `rgb(59, 130, 246)` |
| **HSL** | `hsl(217, 91%, 60%)` |
| **Dark mode variant** | `#60A5FA` / `rgb(96, 165, 250)` / `hsl(217, 93%, 68%)` |
| **Opacity 10%** | `rgba(59, 130, 246, 0.10)` |
| **Opacity 15%** | `rgba(59, 130, 246, 0.15)` |
| **Opacity 20%** | `rgba(59, 130, 246, 0.20)` |
| **Opacity 50%** | `rgba(59, 130, 246, 0.50)` |
| **Opacity 80%** | `rgba(59, 130, 246, 0.80)` |

**Contrast ratios:**

| Background | Ratio | WCAG Level |
|------------|-------|------------|
| Ink Black (#0D0D0D) | 4.7:1 | AA |
| Dark Card (#1C1C1E) | 4.2:1 | AA large text |
| Dark Card with dark variant (#60A5FA) | 4.8:1 | AA |
| Bone White (#F5F2ED) | 4.5:1 | AA (borderline — use 14pt bold+ preferred) |
| Card Surface (#FFFFFF) | 4.1:1 | AA large text only |

**DO:**
- Use for links, info states, study/academic module accent
- Use as Pomodoro timer ring color and study module gradients
- Use as interactive element highlight (tappable labels)

**DO NOT:**
- Never use for body text smaller than 14pt bold on Card Surface (#FFFFFF) — 4.1:1 is marginal
- Never pair adjacent to Protocol Violet without clear spatial separation (similar blue hue family)

---

#### Protocol Violet

| Property | Value |
|----------|-------|
| **Token** | `tempo.color.accent.violet` |
| **Hex** | `#8B5CF6` |
| **RGB** | `rgb(139, 92, 246)` |
| **HSL** | `hsl(263, 90%, 66%)` |
| **Dark mode variant** | `#A78BFA` / `rgb(167, 139, 250)` / `hsl(263, 93%, 76%)` |
| **Opacity 10%** | `rgba(139, 92, 246, 0.10)` |
| **Opacity 15%** | `rgba(139, 92, 246, 0.15)` |
| **Opacity 20%** | `rgba(139, 92, 246, 0.20)` |
| **Opacity 50%** | `rgba(139, 92, 246, 0.50)` |
| **Opacity 80%** | `rgba(139, 92, 246, 0.80)` |

**Contrast ratios:**

| Background | Ratio | WCAG Level |
|------------|-------|------------|
| Ink Black (#0D0D0D) | 3.6:1 | AA large text only |
| Dark Card (#1C1C1E) | 3.2:1 | Large text/icons only |
| Dark Card with dark variant (#A78BFA) | 4.8:1 | AA |
| Bone White (#F5F2ED) | 3.3:1 | Large text/icons only |
| Card Surface (#FFFFFF) | 3.6:1 | Large text/icons only |

**DO:**
- Use for recovery/sleep module accent — ring colors, icons, section headers
- Use at 20pt+ size only or as decorative/icon color
- Always use the dark variant in dark mode

**DO NOT:**
- Never use for body text at any size on any background
- Never use as a button label color (insufficient contrast everywhere)

---

### 3.4 Semantic Colors

#### Mission Green

| Property | Value |
|----------|-------|
| **Token** | `tempo.color.semantic.success` |
| **Hex** | `#22C55E` |
| **RGB** | `rgb(34, 197, 94)` |
| **HSL** | `hsl(142, 71%, 45%)` |
| **Dark mode variant** | `#4ADE80` / `rgb(74, 222, 128)` / `hsl(142, 69%, 58%)` |
| **Opacity 10%** | `rgba(34, 197, 94, 0.10)` |
| **Opacity 15%** | `rgba(34, 197, 94, 0.15)` |
| **Opacity 20%** | `rgba(34, 197, 94, 0.20)` |
| **Opacity 50%** | `rgba(34, 197, 94, 0.50)` |
| **Opacity 80%** | `rgba(34, 197, 94, 0.80)` |

**Contrast ratios:**

| Background | Ratio | WCAG Level |
|------------|-------|------------|
| Ink Black (#0D0D0D) | 6.4:1 | AA |
| Dark Card (#1C1C1E) | 5.8:1 | AA |
| Bone White (#F5F2ED) | 2.5:1 | Fails — must pair with icon on light |
| Card Surface (#FFFFFF) | 2.7:1 | Fails — must pair with icon on light |

**DO:**
- Use for completed tasks, targets hit, positive trends, checkmarks
- Use for checkbox fill animation color
- Use for nutrition module accent
- On light backgrounds, always pair with `checkmark.circle.fill` icon — never text-only green on light

**DO NOT:**
- Never use as text-only indicator on Bone White or Card Surface (2.5:1, fails all levels)
- Never use adjacent to recovery green (same color) without clear module context

---

#### Alert Amber

| Property | Value |
|----------|-------|
| **Token** | `tempo.color.semantic.warning` |
| **Hex** | `#F59E0B` |
| **RGB/HSL** | Same as Command Amber |
| **Dark mode variant** | `#FBBF24` |

Identical to Command Amber. See Command Amber for full spec. Semantic alias exists to distinguish warning context from XP/achievement context in code.

---

#### Fail Red

| Property | Value |
|----------|-------|
| **Token** | `tempo.color.semantic.error` |
| **Hex** | `#DC2626` |
| **RGB** | `rgb(220, 38, 38)` |
| **HSL** | `hsl(0, 72%, 51%)` |
| **Dark mode variant** | `#F87171` / `rgb(248, 113, 113)` / `hsl(0, 91%, 71%)` |
| **Opacity 10%** | `rgba(220, 38, 38, 0.10)` — destructive button pressed state |
| **Opacity 15%** | `rgba(220, 38, 38, 0.15)` |
| **Opacity 20%** | `rgba(220, 38, 38, 0.20)` |
| **Opacity 50%** | `rgba(220, 38, 38, 0.50)` |
| **Opacity 80%** | `rgba(220, 38, 38, 0.80)` |

**Contrast ratios:**

| Background | Ratio | WCAG Level |
|------------|-------|------------|
| Bone White (#F5F2ED) | 5.3:1 | AA |
| Card Surface (#FFFFFF) | 5.7:1 | AA |
| Ink Black (#0D0D0D) | 3.5:1 | AA large text only |
| Dark Card (#1C1C1E) | 3.1:1 | Large text/icons only |
| Dark Card with dark variant (#F87171) | 5.4:1 | AA |

**DO:**
- Use for failed targets, validation errors, destructive actions, streak breaks
- Use for error input borders (2pt weight)
- Use for low recovery zone ring

**DO NOT:**
- Never use as body text on dark backgrounds without the dark variant (#F87171)
- Never place adjacent to Signal Red — use only one red per visual context

---

#### Intel Blue

| Property | Value |
|----------|-------|
| **Token** | `tempo.color.semantic.info` |
| **Hex** | `#3B82F6` |
| **RGB/HSL** | Same as Electric Blue |
| **Dark mode variant** | `#60A5FA` |

Identical to Electric Blue. Semantic alias for informational context (banners, tooltips, onboarding). See Electric Blue for full spec.

---

### 3.5 Recovery Zone Colors

Modeled after Whoop's recovery spectrum. Used in recovery score rings, zone badges, and background tints.

| Token | Name | Hex | RGB | HSL | Zone | Usage |
|-------|------|-----|-----|-----|------|-------|
| `tempo.color.recovery.green` | Green Zone | `#22C55E` | 34, 197, 94 | 142, 71%, 45% | 67-100% | Full recovery ring, "GO" state |
| `tempo.color.recovery.green.bg` | Green Zone Tint | `#F0FDF4` | 240, 253, 244 | 138, 76%, 97% | 67-100% | Card background tint |
| `tempo.color.recovery.yellow` | Yellow Zone | `#EAB308` | 234, 179, 8 | 45, 93%, 47% | 34-66% | Moderate recovery, "CAUTION" |
| `tempo.color.recovery.yellow.bg` | Yellow Zone Tint | `#FEFCE8` | 254, 252, 232 | 55, 92%, 95% | 34-66% | Card background tint |
| `tempo.color.recovery.red` | Red Zone | `#DC2626` | 220, 38, 38 | 0, 72%, 51% | 0-33% | Low recovery, "STOP" state |
| `tempo.color.recovery.red.bg` | Red Zone Tint | `#FEF2F2` | 254, 242, 242 | 0, 86%, 97% | 0-33% | Card background tint |

> **Boundary rule:** Green = `score >= 67.0`, Yellow = `score >= 34.0 && score < 67.0`, Red = `score < 34.0`. Boundary values (67.0, 34.0) belong to the higher zone. See DATA_MODELS_IOS.md `RecoveryZone.init(score:)` for canonical Swift implementation.

**Dark mode variants:**

| Light | Dark | Dark Hex |
|-------|------|----------|
| Green Zone #22C55E | Green Zone Dark | `#4ADE80` |
| Green Zone Tint #F0FDF4 | Green Zone Tint Dark | `#052E16` |
| Yellow Zone #EAB308 | Yellow Zone Dark | `#FACC15` |
| Yellow Zone Tint #FEFCE8 | Yellow Zone Tint Dark | `#422006` |
| Red Zone #DC2626 | Red Zone Dark | `#F87171` |
| Red Zone Tint #FEF2F2 | Red Zone Tint Dark | `#450A0A` |

---

### 3.6 Background Colors

| Token | Name | Hex | RGB | HSL | Usage |
|-------|------|-----|-----|-----|-------|
| `tempo.color.bg.primary` | Primary Background | `#F5F2ED` | 245, 242, 237 | 37, 33%, 95% | Main screen background, scroll views |
| `tempo.color.bg.secondary` | Secondary Background | `#EDEAE4` | 237, 234, 228 | 40, 24%, 91% | Grouped table backgrounds, inset sections |
| `tempo.color.bg.tertiary` | Tertiary Background | `#E5E2DC` | 229, 226, 220 | 40, 16%, 88% | Nested grouped content, search bar fills |

### 3.7 Surface Colors

| Token | Name | Hex | RGB | Usage |
|-------|------|-----|-----|-------|
| `tempo.color.surface.card` | Card Surface | `#FFFFFF` | 255, 255, 255 | Card backgrounds, list item backgrounds |
| `tempo.color.surface.sheet` | Sheet Surface | `#FFFFFF` | 255, 255, 255 | Bottom sheets, modal backgrounds |
| `tempo.color.surface.elevated` | Elevated Surface | `#FFFFFF` | 255, 255, 255 | Popovers, dropdown menus (differentiated by shadow) |
| `tempo.color.surface.overlay` | Overlay Scrim | `#0D0D0D` @ 40% | 13, 13, 13 | Modal backdrop overlay |

### 3.8 Text Colors

| Token | Name | Hex | RGB | Usage | Contrast on Bone |
|-------|------|-----|-----|-------|------------------|
| `tempo.color.text.primary` | Primary Text | `#0D0D0D` | 13, 13, 13 | Headlines, body text, primary labels | 17.4:1 (AAA) |
| `tempo.color.text.secondary` | Secondary Text | `#4B5563` | 75, 85, 99 | Subtitles, descriptions | 7.2:1 (AAA) |
| `tempo.color.text.tertiary` | Tertiary Text | `#6B7280` | 107, 114, 128 | Captions, timestamps, metadata | 4.8:1 (AA) |
| `tempo.color.text.disabled` | Disabled Text | `#9CA3AF` | 156, 163, 175 | Disabled labels, placeholders | 3.1:1 (exempt) |
| `tempo.color.text.inverse` | Inverse Text | `#F5F2ED` | 245, 242, 237 | Text on dark/colored backgrounds | N/A |

### 3.9 Border & Divider Colors

| Token | Name | Hex | RGB | Usage |
|-------|------|-----|-----|-------|
| `tempo.color.border.default` | Default Border | `#E5E7EB` | 229, 231, 235 | Card borders, input field borders |
| `tempo.color.border.focused` | Focused Border | `#0D0D0D` | 13, 13, 13 | Focused input fields, selected states |
| `tempo.color.border.error` | Error Border | `#DC2626` | 220, 38, 38 | Validation error input fields |
| `tempo.color.divider.default` | Default Divider | `#E5E7EB` | 229, 231, 235 | List separators, section dividers |
| `tempo.color.divider.heavy` | Heavy Divider | `#D1D5DB` | 209, 213, 219 | Major section breaks |

### 3.10 Gradient Definitions

Every gradient specifies exact degree, color stops with percentages, and usage context.

#### Score Ring Gradient

| Property | Value |
|----------|-------|
| **Token** | `tempo.gradient.score-ring` |
| **Type** | Angular (conic), following ring path |
| **Stop 1** | `#E63946` at 0% (12 o'clock position) |
| **Stop 2** | `#DC2626` at 100% (end of ring) |
| **Dark stops** | `#FF4D5A` at 0% → `#E63946` at 100% |
| **Usage** | Main daily score ring on dashboard, module score rings |
| **SwiftUI** | `AngularGradient(colors: [Color.Tempo.signal, Color(red: 0.86, green: 0.15, blue: 0.15)], center: .center, startAngle: .degrees(-90), endAngle: .degrees(progressAngle - 90))` |

#### XP Progress Gradient

| Property | Value |
|----------|-------|
| **Token** | `tempo.gradient.xp-bar` |
| **Type** | Linear |
| **Direction** | 0 degrees (left to right) |
| **Stop 1** | `#F59E0B` at 0% |
| **Stop 2** | `#EAB308` at 100% |
| **Dark stops** | `#FBBF24` at 0% → `#F59E0B` at 100% |
| **Usage** | XP progress bars, level progress indicators |

#### Recovery High Gradient

| Property | Value |
|----------|-------|
| **Token** | `tempo.gradient.recovery-high` |
| **Type** | Linear |
| **Direction** | 270 degrees (bottom to top) |
| **Stop 1** | `#22C55E` at 0% (bottom) |
| **Stop 2** | `#16A34A` at 100% (top) |
| **Dark stops** | `#4ADE80` at 0% → `#22C55E` at 100% |
| **Usage** | Recovery ring when green zone (67-100%) |

#### Recovery Mid Gradient

| Property | Value |
|----------|-------|
| **Token** | `tempo.gradient.recovery-mid` |
| **Type** | Linear |
| **Direction** | 270 degrees (bottom to top) |
| **Stop 1** | `#EAB308` at 0% |
| **Stop 2** | `#CA8A04` at 100% |
| **Dark stops** | `#FACC15` at 0% → `#EAB308` at 100% |
| **Usage** | Recovery ring when yellow zone (34-66%) |

#### Recovery Low Gradient

| Property | Value |
|----------|-------|
| **Token** | `tempo.gradient.recovery-low` |
| **Type** | Linear |
| **Direction** | 270 degrees (bottom to top) |
| **Stop 1** | `#DC2626` at 0% |
| **Stop 2** | `#B91C1C` at 100% |
| **Dark stops** | `#F87171` at 0% → `#DC2626` at 100% |
| **Usage** | Recovery ring when red zone (0-33%) |

#### Hero Dark Gradient

| Property | Value |
|----------|-------|
| **Token** | `tempo.gradient.hero-dark` |
| **Type** | Linear |
| **Direction** | 180 degrees (top to bottom) |
| **Stop 1** | `#0D0D0D` at 0% |
| **Stop 2** | `#1F1F1F` at 100% |
| **Dark stops** | `#0D0D0D` at 0% → `#1A1A1A` at 100% |
| **Usage** | Dark hero sections, dashboard header background |

#### Bottom Scrim Gradient

| Property | Value |
|----------|-------|
| **Token** | `tempo.gradient.scrim` |
| **Type** | Linear |
| **Direction** | 180 degrees (top to bottom) |
| **Stop 1** | `#0D0D0D` at 0% opacity, position 0% |
| **Stop 2** | `#0D0D0D` at 60% opacity, position 100% |
| **Usage** | Text legibility overlay when content sits over images |

#### Study Module Gradient

| Property | Value |
|----------|-------|
| **Token** | `tempo.gradient.study` |
| **Type** | Linear |
| **Direction** | 135 degrees (top-left to bottom-right) |
| **Stop 1** | `#3B82F6` at 0% |
| **Stop 2** | `#2563EB` at 100% |
| **Dark stops** | `#60A5FA` at 0% → `#3B82F6` at 100% |
| **Usage** | Study timer background accent, study module hero |

#### Skeleton Shimmer Gradient

| Property | Value |
|----------|-------|
| **Token** | `tempo.gradient.card-shimmer` |
| **Type** | Linear, animated |
| **Direction** | 20 degrees (slight diagonal for organic feel) |
| **Stop 1** | `#E5E7EB` at 0% |
| **Stop 2** | `#F9FAFB` at 50% |
| **Stop 3** | `#E5E7EB` at 100% |
| **Dark stops** | `#38383A` at 0% → `#48484A` at 50% → `#38383A` at 100% |
| **Animation** | Translates from -100% to +100% over 1.5s, ease-in-out, infinite loop |
| **Usage** | All skeleton loading placeholders |

#### Achievement Shimmer Gradient

| Property | Value |
|----------|-------|
| **Token** | `tempo.gradient.achievement-shimmer` |
| **Type** | Linear |
| **Direction** | 135 degrees |
| **Stop 1** | `#FFFFFF` at 0% opacity, position 0% |
| **Stop 2** | `#FFFFFF` at 40% opacity, position 50% |
| **Stop 3** | `#FFFFFF` at 0% opacity, position 100% |
| **Animation** | Single sweep left-to-right, 300ms, on achievement unlock |
| **Usage** | Gold shimmer overlay on achievement card unlock animation |

---

### 3.11 Color Opacity Quick Reference

For every primary, secondary, accent, and semantic color, the following opacity variants exist:

| Opacity Level | Token Suffix | Common Usage |
|---------------|-------------|--------------|
| 100% (full) | (none) | Primary usage — fills, text, icons |
| 80% | `.opacity80` | Text on semi-transparent surfaces |
| 50% | `.opacity50` | Locked/unavailable achievement cards |
| 20% | `.opacity20` | Track colors for progress rings, shadow glows |
| 15% | `.opacity15` | Badge backgrounds, subtle tints |
| 10% | `.opacity10` | Pressed state backgrounds, hover tints |
| 8% | `.opacity08` | Ghost button pressed states |
| 5% | `.opacity05` | Secondary button pressed backgrounds |

---

### 3.12 Full Dark Mode Color Mapping

| Light Token | Light Hex | Dark Hex | Dark RGB | Notes |
|-------------|-----------|----------|----------|-------|
| `tempo.color.bg.primary` | `#F5F2ED` | `#0D0D0D` | 13, 13, 13 | True black for OLED |
| `tempo.color.bg.secondary` | `#EDEAE4` | `#1A1A1A` | 26, 26, 26 | Slight elevation |
| `tempo.color.bg.tertiary` | `#E5E2DC` | `#262626` | 38, 38, 38 | Nested content |
| `tempo.color.surface.card` | `#FFFFFF` | `#1C1C1E` | 28, 28, 30 | iOS system dark card |
| `tempo.color.surface.sheet` | `#FFFFFF` | `#2C2C2E` | 44, 44, 46 | Elevated sheet |
| `tempo.color.surface.elevated` | `#FFFFFF` | `#3A3A3C` | 58, 58, 60 | Popover/dropdown |
| `tempo.color.surface.overlay` | `#0D0D0D` @ 40% | `#000000` @ 50% | 0, 0, 0 | Stronger scrim in dark |
| `tempo.color.text.primary` | `#0D0D0D` | `#F5F2ED` | 245, 242, 237 | Inverted |
| `tempo.color.text.secondary` | `#4B5563` | `#A1A1AA` | 161, 161, 170 | Contrast on #1C1C1E: 6.1:1 (AA) |
| `tempo.color.text.tertiary` | `#6B7280` | `#8E8E93` | 142, 142, 147 | Contrast on #1C1C1E: 5.0:1 (AA) — CHANGED from #71717A (3.9:1, failed AA normal text) |
| `tempo.color.text.disabled` | `#9CA3AF` | `#52525B` | 82, 82, 91 | Muted for dark |
| `tempo.color.text.inverse` | `#F5F2ED` | `#0D0D0D` | 13, 13, 13 | Inverted |
| `tempo.color.border.default` | `#E5E7EB` | `#38383A` | 56, 56, 58 | Subtle dark borders |
| `tempo.color.border.focused` | `#0D0D0D` | `#F5F2ED` | 245, 242, 237 | Inverted |
| `tempo.color.divider.default` | `#E5E7EB` | `#38383A` | 56, 56, 58 | Matches dark border |
| `tempo.color.divider.heavy` | `#D1D5DB` | `#48484A` | 72, 72, 74 | Slightly brighter |
| `tempo.color.primary.signal` | `#E63946` | `#FF4D5A` | 255, 77, 90 | Brighter red for dark bg |
| `tempo.color.accent.amber` | `#F59E0B` | `#FBBF24` | 251, 191, 36 | Brighter amber |
| `tempo.color.accent.electric` | `#3B82F6` | `#60A5FA` | 96, 165, 250 | Brighter blue |
| `tempo.color.accent.violet` | `#8B5CF6` | `#A78BFA` | 167, 139, 250 | Brighter violet |
| `tempo.color.semantic.success` | `#22C55E` | `#4ADE80` | 74, 222, 128 | Brighter green |
| `tempo.color.semantic.warning` | `#F59E0B` | `#FBBF24` | 251, 191, 36 | Brighter amber |
| `tempo.color.semantic.error` | `#DC2626` | `#F87171` | 248, 113, 113 | Brighter red |
| `tempo.color.semantic.info` | `#3B82F6` | `#60A5FA` | 96, 165, 250 | Brighter blue |
| `tempo.color.recovery.green` | `#22C55E` | `#4ADE80` | 74, 222, 128 | Brighter for dark |
| `tempo.color.recovery.green.bg` | `#F0FDF4` | `#052E16` | 5, 46, 22 | Dark tint |
| `tempo.color.recovery.yellow` | `#EAB308` | `#FACC15` | 250, 204, 21 | Brighter for dark |
| `tempo.color.recovery.yellow.bg` | `#FEFCE8` | `#422006` | 66, 32, 6 | Dark tint |
| `tempo.color.recovery.red` | `#DC2626` | `#F87171` | 248, 113, 113 | Brighter for dark |
| `tempo.color.recovery.red.bg` | `#FEF2F2` | `#450A0A` | 69, 10, 10 | Dark tint |

### 3.13 WCAG AAA Contrast Verification Matrix

All text-bearing combinations must meet WCAG AAA (7:1 for normal text, 4.5:1 for large text 18pt+/bold 14pt+). Decorative and disabled elements are exempt.

| Foreground | Background | Ratio | AAA Normal (7:1) | AAA Large (4.5:1) | Status |
|------------|------------|-------|-------------------|--------------------|----|
| Ink Black | Bone White | 17.4:1 | PASS | PASS | Primary body text |
| Ink Black | Card Surface | 19.3:1 | PASS | PASS | Card body text |
| Ink Black | Secondary Bg | 15.8:1 | PASS | PASS | Grouped section text |
| Bone White | Ink Black | 17.4:1 | PASS | PASS | Dark mode body text |
| Bone White | Steel Gray | 12.5:1 | PASS | PASS | Dark surface text |
| Bone White | Dark Card | 14.1:1 | PASS | PASS | Dark mode cards |
| Secondary Text | Bone White | 7.2:1 | PASS | PASS | Subtitles, descriptions |
| Secondary Text | Card Surface | 7.8:1 | PASS | PASS | Card subtitles |
| Tertiary Text | Bone White | 4.8:1 | FAIL (use large only) | PASS | Captions 12pt+ only |
| Signal Red | Bone White | 4.6:1 | FAIL | PASS | Large text/icons only |
| Signal Red | Card Surface | 4.9:1 | FAIL | PASS | Large text/icons only |
| Signal Red Dark | Dark Card | 4.6:1 | FAIL | PASS | Dark mode, large only |
| Electric Blue | Bone White | 4.5:1 | FAIL | PASS | Links 14pt bold+ only |
| Electric Blue Dark | Dark Card | 4.8:1 | FAIL | PASS | Dark mode links |
| Command Amber | Ink Black | 8.2:1 | PASS | PASS | XP text on dark surfaces |
| Mission Green | Ink Black | 6.4:1 | FAIL (6.4) | PASS | Icon+text only, 14pt bold+ |
| Fail Red | Bone White | 5.3:1 | FAIL | PASS | Error text 14pt bold+ |
| Fail Red Dark | Dark Card | 5.4:1 | FAIL | PASS | Dark mode errors |
| Dark Secondary Text (#A1A1AA) | Dark Card | 6.1:1 | FAIL (6.1) | PASS | Dark mode subtitles |
| Dark Tertiary Text (#8E8E93) | Dark Card | 5.0:1 | FAIL | PASS | Dark mode captions (12pt+) |

**Rule**: For any combination that fails AAA for normal text, restrict usage to:
- Icons (any size)
- Bold text 14pt or larger
- Regular text 18pt or larger
- Pair with a secondary indicator (icon shape, pattern) for accessibility

---

## 4. Typography

### 4.1 Font Family

| Role | Font | Reasoning |
|------|------|-----------|
| **Primary** | **SF Pro Display** (titles, headlines) / **SF Pro Text** (body, captions) | System font ensures maximum performance, native feel, and automatic optical sizing. SF Pro's geometric backbone matches Tempo's disciplined personality. No custom font download overhead. |
| **Monospace** | **SF Mono** | Used for data values, timers, counters. Native to iOS. Clean, technical, authoritative. |
| **Numeric Display** | **SF Pro Rounded Bold** | Used exclusively for large score displays and XP counts. The rounded variant softens massive numbers slightly, preventing them from feeling aggressive at 64pt+. |

### 4.2 Type Scale

All sizes in points (pt). Line height in pt. Letter spacing in pt (0 = system default).

#### Display Styles (SF Pro Rounded Bold)

| Style | Font | Weight | Size | Line Height | Letter Spacing | Usage |
|-------|------|--------|------|-------------|----------------|-------|
| **Score Display** | SF Pro Rounded | Bold (700) | 64pt | 72pt | -1.0pt | Daily composite score (0-100) on dashboard |
| **Score Display Small** | SF Pro Rounded | Bold (700) | 48pt | 54pt | -0.8pt | Module-specific scores on detail screens |
| **XP Display** | SF Pro Rounded | Bold (700) | 36pt | 42pt | -0.5pt | Total XP count on profile |
| **Timer Display** | SF Mono | Bold (700) | 56pt | 64pt | 0pt | Pomodoro timer, workout rest timer |
| **Timer Display Small** | SF Mono | Semibold (600) | 40pt | 46pt | 0pt | Secondary timer (elapsed time, set timer) |

#### Title Styles (SF Pro Display)

| Style | Font | Weight | Size | Line Height | Letter Spacing | Usage |
|-------|------|--------|------|-------------|----------------|-------|
| **Large Title** | SF Pro Display | Bold (700) | 34pt | 41pt | 0.37pt | Top-level screen titles (Dashboard, Profile) |
| **Title 1** | SF Pro Display | Bold (700) | 28pt | 34pt | 0.36pt | Section headers within scrollable content |
| **Title 2** | SF Pro Display | Bold (700) | 22pt | 28pt | 0.35pt | Card titles, module headers |
| **Title 3** | SF Pro Display | Semibold (600) | 20pt | 25pt | 0.38pt | Subsection titles, dialog titles |

#### Body Styles (SF Pro Text)

| Style | Font | Weight | Size | Line Height | Letter Spacing | Usage |
|-------|------|--------|------|-------------|----------------|-------|
| **Headline** | SF Pro Text | Semibold (600) | 17pt | 22pt | -0.41pt | List row titles, bold inline labels |
| **Subheadline** | SF Pro Text | Regular (400) | 15pt | 20pt | -0.24pt | List row subtitles, secondary descriptors |
| **Body** | SF Pro Text | Regular (400) | 17pt | 22pt | -0.41pt | Primary readable text, descriptions, instructions |
| **Body Bold** | SF Pro Text | Semibold (600) | 17pt | 22pt | -0.41pt | Emphasized body text, inline labels |
| **Callout** | SF Pro Text | Regular (400) | 16pt | 21pt | -0.32pt | Callout boxes, secondary body text |
| **Caption 1** | SF Pro Text | Regular (400) | 12pt | 16pt | 0pt | Timestamps, metadata, chart axis labels |
| **Caption 2** | SF Pro Text | Regular (400) | 11pt | 13pt | 0.07pt | Fine print, legal text, tertiary metadata |
| **Footnote** | SF Pro Text | Regular (400) | 13pt | 18pt | -0.08pt | Footnotes, help text below inputs |

#### Data Styles (SF Mono)

| Style | Font | Weight | Size | Line Height | Letter Spacing | Usage |
|-------|------|--------|------|-------------|----------------|-------|
| **Data Large** | SF Mono | Bold (700) | 24pt | 30pt | 0pt | In-card stat values (e.g., "2,340 cal", "85 kg") |
| **Data Medium** | SF Mono | Semibold (600) | 17pt | 22pt | 0pt | Inline data values, table cells |
| **Data Small** | SF Mono | Medium (500) | 13pt | 18pt | 0pt | Secondary data, chart tooltips |

#### Specialized Label Styles

| Style | Font | Weight | Size | Line Height | Letter Spacing | Color | Usage |
|-------|------|--------|------|-------------|----------------|-------|-------|
| **Drill Label** | SF Pro Text | Bold (700) | 12pt | 16pt | +1.5pt | Command Amber | "DRILL SERGEANT" label on prescription cards |
| **Orders Label** | SF Pro Text | Bold (700) | 12pt | 16pt | +2.0pt | Command Amber | "ORDERS" label on drill sergeant alerts |
| **Zone Label** | SF Pro Text | Bold (700) | 12pt | 16pt | +1.0pt | (zone color) | "FOCUS", "BREAK", "REST" labels |
| **Module Tag** | SF Pro Text | Semibold (600) | 10pt | 12pt | +0.5pt | (module color) | Module identifier tags |

### 4.3 Dynamic Type Support

Tempo MUST support Dynamic Type across all text styles. Implementation rules:

| Our Style | Maps to UIFont.TextStyle | Scales With | Max Scale |
|-----------|-------------------------|-------------|-----------|
| Large Title | `.largeTitle` | System setting | Unlimited |
| Title 1 | `.title1` | System setting | Unlimited |
| Title 2 | `.title2` | System setting | Unlimited |
| Title 3 | `.title3` | System setting | Unlimited |
| Headline | `.headline` | System setting | Unlimited |
| Subheadline | `.subheadline` | System setting | Unlimited |
| Body | `.body` | System setting | Unlimited |
| Callout | `.callout` | System setting | Unlimited |
| Caption 1 | `.caption1` | System setting | Unlimited |
| Caption 2 | `.caption2` | System setting | Unlimited |
| Footnote | `.footnote` | System setting | Unlimited |
| Score Display | `.largeTitle` | **Capped** at 1.3x | 83pt |
| Score Display Small | `.largeTitle` | **Capped** at 1.3x | 62pt |
| XP Display | `.title1` | **Capped** at 1.3x | 47pt |
| Timer Display | `.largeTitle` | **Capped** at 1.2x | 67pt |
| Timer Display Small | `.title1` | **Capped** at 1.2x | 48pt |
| Data Large | `.title2` | **Capped** at 1.3x | 31pt |
| Data Medium | `.body` | System setting | Unlimited |
| Data Small | `.footnote` | System setting | Unlimited |

**Dynamic Type Scaling Table:**

| Size Category | Scale | Score Display | Timer Display |
|---------------|-------|---------------|---------------|
| xSmall | 0.82x | 52pt | 46pt |
| Small | 0.88x | 56pt | 49pt |
| Medium (default) | 1.0x | 64pt | 56pt |
| Large | 1.06x | 68pt | 59pt |
| xLarge | 1.12x | 72pt | 63pt |
| xxLarge | 1.18x | 76pt | 66pt |
| xxxLarge | 1.24x | 79pt | 67pt (capped) |
| AX1 | 1.35x | 83pt (capped) | 67pt (capped) |
| AX2 | 1.53x | 83pt (capped) | 67pt (capped) |
| AX3 | 1.70x | 83pt (capped) | 67pt (capped) |
| AX4 | 1.94x | 83pt (capped) | 67pt (capped) |
| AX5 | 2.35x | 83pt (capped) | 67pt (capped) |

**Rules:**
- All text MUST use `UIFontMetrics` for proper scaling
- In SwiftUI, use `.dynamicTypeSize(...DynamicTypeSize.xxxLarge)` on display/timer text to enforce caps
- Display/timer styles cap their maximum size to prevent layout breakage
- Never set a fixed font size without also configuring a `maximumPointSize`
- Line heights scale proportionally with font size (maintain the base ratio, e.g., Score Display 64pt/72pt = 1.125x line height ratio at all sizes)
- Test at every accessibility size: xSmall through AX5
- Layouts must reflow: horizontal label+value pairs stack vertically at AX1+
- Card heights must be flexible (never fixed height for text-containing cards)
- At AX1+, consider using `ViewThatFits` or `@Environment(\.dynamicTypeSize)` to switch layouts

---

## 5. Spacing System

### 5.1 Base Unit

**Base unit: 4pt**. All spacing values MUST be multiples of 4. The sole exception is `tempo.space.2xs` at 2pt, used only for icon-to-text gaps in tight layouts.

### 5.2 Spacing Scale

| Token | Name | Value | Common Usage |
|-------|------|-------|-------------|
| `tempo.space.2xs` | 2XS | 2pt | Icon-to-text gap in tight layouts (exception to 4pt rule, used sparingly) |
| `tempo.space.xs` | XS | 4pt | Minimum gap between related elements, inner icon padding |
| `tempo.space.sm` | SM | 8pt | Gap between label and value, between stacked icons |
| `tempo.space.md` | MD | 12pt | Card internal element gaps, list item vertical padding |
| `tempo.space.lg` | LG | 16pt | Standard padding (card padding, screen edge), section gaps |
| `tempo.space.xl` | XL | 20pt | Screen edge padding (leading/trailing) |
| `tempo.space.2xl` | 2XL | 24pt | Between card sections, between major UI groups |
| `tempo.space.3xl` | 3XL | 32pt | Between screen sections, above/below section headers |
| `tempo.space.4xl` | 4XL | 40pt | Major section separation, dashboard header spacing |
| `tempo.space.5xl` | 5XL | 48pt | Top-of-screen spacing (below safe area), screen bottom padding |

### 5.3 Component-Specific Padding Rules

| Component | Padding | Notes |
|-----------|---------|-------|
| **Card** | 16pt all sides | Standard card. Content hugs edges with 16pt inset. |
| **Card (compact)** | 12pt all sides | Small cards in grids (dashboard quadrants) |
| **Button (primary/secondary)** | 24pt horizontal, 14pt vertical | Minimum touch target 44x44pt |
| **Button (small)** | 12pt horizontal, 8pt vertical | Compact contexts only. Still meets 44x44 touch target with minimum width. |
| **List item** | 16pt leading, 16pt trailing, 12pt top, 12pt bottom | Standard inset grouped list |
| **Section header** | 20pt leading, 20pt trailing, 32pt top, 8pt bottom | Section title above content group |
| **Screen edges** | 20pt leading, 20pt trailing | All scrollable content. 16pt on iPhone SE. 24pt on iPad. |
| **Bottom sheet** | 20pt horizontal, 16pt top (below grabber), 34pt bottom (above home indicator) | Standard bottom sheet |
| **Modal** | 20pt all sides, 24pt top | Modal dialogs |
| **Text field** | 12pt horizontal, 12pt vertical | Standard text input |
| **Tab bar** | System default | Follow iOS HIG exactly |
| **Navigation bar** | System default | Follow iOS HIG exactly |

### 5.4 Margin Rules Between Components

| Between | Margin |
|---------|--------|
| Stacked cards | 12pt |
| Card and section header | 8pt |
| Section header and next section | 32pt |
| Dashboard quadrant cards (grid gap) | 12pt |
| List items (inset divider) | 0pt (divider separates) |
| Button stack (vertical) | 12pt |
| Button stack (horizontal) | 8pt |
| Label above input | 8pt |
| Input and helper/error text below | 4pt |
| Chart and its legend | 16pt |

### 5.5 Safe Area Handling

| Edge | Rule |
|------|------|
| **Top** | Content starts 8pt below the safe area inset. Navigation bar content follows system behavior. |
| **Bottom** | All scrollable content has 48pt padding above the home indicator safe area. Tab bar sits on the safe area naturally. Bottom sheets account for safe area in their bottom padding. |
| **Leading/Trailing** | 20pt from safe area edges. iPhone SE: 16pt. iPad: 24pt. |
| **Keyboard** | All inputs and their parent scroll views adjust for keyboard with 16pt of additional breathing room above the keyboard. Use `UIKeyboardLayoutGuide`. |

---

## 6. Depth & Elevation System

Five distinct elevation levels, each with precise shadow definitions for both light and dark mode. In dark mode, shadows are nearly invisible — edges are defined by surface color differentiation and 0.5pt borders instead.

### 6.1 Elevation Levels

#### Elevation 0 — Base

| Property | Light Mode | Dark Mode |
|----------|------------|-----------|
| **Surface** | `#F5F2ED` (Bone White) | `#0D0D0D` (Ink Black) |
| **Shadow** | None | None |
| **Border** | None | None |
| **Usage** | Screen background, scroll view background | Screen background |

#### Elevation 1 — Recessed

| Property | Light Mode | Dark Mode |
|----------|------------|-----------|
| **Surface** | `#EDEAE4` (Secondary Bg) | `#1A1A1A` |
| **Shadow** | None (differentiated by color only) | None |
| **Border** | None | None |
| **Usage** | Grouped table backgrounds, inset sections | Grouped table backgrounds |

#### Elevation 2 — Card

| Property | Light Mode | Dark Mode |
|----------|------------|-----------|
| **Surface** | `#FFFFFF` | `#1C1C1E` |
| **Shadow X** | 0pt | None |
| **Shadow Y** | 2pt | None |
| **Shadow Blur** | 8pt | None |
| **Shadow Spread** | 0pt | None |
| **Shadow Color** | `rgba(13, 13, 13, 0.06)` | None |
| **Border** | None | 0.5pt `#38383A` |
| **Usage** | Cards, list item backgrounds | Cards, list item backgrounds |

**SwiftUI modifier chain** (requires `@Environment(\.colorScheme) var colorScheme`)**:**
```swift
.background(Color.Tempo.surfaceCard)
.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
.shadow(
    color: Color.Tempo.ink.opacity(colorScheme == .dark ? 0 : 0.06),
    radius: 4, x: 0, y: 2
)
// Dark mode: replace shadow with overlay border
.overlay(
    RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(Color.Tempo.borderDefault, lineWidth: 0.5)
        .opacity(colorScheme == .dark ? 1 : 0)
)
```

#### Elevation 3 — Sheet / Floating

| Property | Light Mode | Dark Mode |
|----------|------------|-----------|
| **Surface** | `#FFFFFF` | `#2C2C2E` |
| **Shadow X** | 0pt | 0pt |
| **Shadow Y** | -4pt (sheets), 4pt (FAB) | 0pt |
| **Shadow Blur** | 20pt | 4pt |
| **Shadow Spread** | 0pt | 0pt |
| **Shadow Color** | `rgba(13, 13, 13, 0.15)` | `rgba(0, 0, 0, 0.40)` |
| **Border** | None | 0.5pt `#48484A` |
| **Usage** | Bottom sheets, drawers, FAB | Bottom sheets, FAB |

**FAB-specific shadow (light):**
```swift
.shadow(color: Color.Tempo.ink.opacity(0.20), radius: 6, x: 0, y: 4)
```

**FAB-specific shadow (dark):**
```swift
.shadow(color: Color.black.opacity(0.40), radius: 6, x: 0, y: 4)
```

#### Elevation 4 — Popover

| Property | Light Mode | Dark Mode |
|----------|------------|-----------|
| **Surface** | `#FFFFFF` | `#3A3A3C` |
| **Shadow X** | 0pt | 0pt |
| **Shadow Y** | 8pt | 2pt |
| **Shadow Blur** | 32pt | 8pt |
| **Shadow Spread** | -2pt | 0pt |
| **Shadow Color** | `rgba(13, 13, 13, 0.18)` | `rgba(0, 0, 0, 0.50)` |
| **Border** | None | 0.5pt `#545456` |
| **Usage** | Popovers, dropdown menus, context menus, tooltips | Same |

#### Elevation 5 — Overlay

| Property | Light Mode | Dark Mode |
|----------|------------|-----------|
| **Surface** | N/A (content behind scrim) | N/A |
| **Scrim** | `rgba(13, 13, 13, 0.40)` | `rgba(0, 0, 0, 0.50)` |
| **Usage** | Modal backdrop, bottom sheet backdrop | Same |

### 6.2 Special Shadow: Drill Sergeant Glow

The Drill Sergeant Alert and Prescription Card use a unique colored shadow to convey authority and urgency. This is the only shadow that uses a non-neutral color.

| Property | Value |
|----------|-------|
| **Shadow X** | 0pt |
| **Shadow Y** | 0pt |
| **Shadow Blur** | 24pt (alert), 16pt (prescription card) |
| **Shadow Spread** | 0pt |
| **Shadow Color (alert)** | `rgba(230, 57, 70, 0.20)` — Signal Red glow |
| **Shadow Color (prescription)** | `rgba(230, 57, 70, 0.15)` — Subtler red glow |
| **Both modes** | Identical — these components use Ink Black background in both light and dark |

```swift
.shadow(color: Color.Tempo.signal.opacity(0.20), radius: 12, x: 0, y: 0)
```

### 6.3 Stat Card Shadow (Light only)

| Property | Value |
|----------|-------|
| **Shadow X** | 0pt |
| **Shadow Y** | 1pt |
| **Shadow Blur** | 4pt |
| **Shadow Spread** | 0pt |
| **Shadow Color** | `rgba(13, 13, 13, 0.04)` |
| **Usage** | Stat cards — lighter than standard cards for subtlety |

---

## 7. Iconography

### 7.1 Icon Style

**Primary source: SF Symbols** (Apple's system icon library). Use **filled variants** as the default for all interactive/primary icons. Outline variants are reserved for unselected tab states only.

Where SF Symbols lacks a suitable glyph, use custom icons that match SF Symbols' design language:
- 2pt stroke weight at 24pt size (scales proportionally)
- Rounded line caps and joins
- Centered within a square bounding box
- Designed on a 24x24pt grid with 2pt padding (20x20pt live area)

### 7.2 Icon Sizes

| Context | Size | Weight | Color Token | Padding | Notes |
|---------|------|--------|-------------|---------|-------|
| **Tab bar** | 24pt | Regular (unselected), Bold (selected) | Unselected: `tempo.color.secondary.concrete` / Selected: `tempo.color.primary.signal` | System default | iOS handles hit area |
| **Navigation bar** | 22pt | Regular | `tempo.color.primary.signal` | System default | Back, share, edit, settings |
| **Inline with text** | Match text pt size | Match text weight | Matches text color | 0pt | Within body text, list labels |
| **Card header icon** | 20pt | Semibold | Module accent color | 0pt | Module icon in card headers |
| **Feature/action icon** | 28pt | Medium | Context-dependent | 8pt touchable padding | Start workout, log meal |
| **Large decorative** | 48pt | Light or Ultralight | `tempo.color.secondary.ash` | 0pt | Empty states, onboarding |
| **Achievement badge icon** | 32pt (64pt badge) / 18pt (40pt badge) | Bold | `#FFFFFF` | Centered in circle | Inside badge circles |
| **Status indicator** | 12pt | Bold | Semantic color | 0pt | Dots, mini status |
| **Toast/banner icon** | 20pt | Semibold | Semantic color | 0pt | Leading icon in notifications |
| **Input leading icon** | 20pt | Regular | `tempo.color.secondary.concrete` | 12pt from leading edge | Optional prefix in text fields |
| **Clear button** | 18pt | Regular | `tempo.color.secondary.ash` | 12pt from trailing edge | Text field clear, search clear |

### 7.3 Complete Icon Inventory

Every icon used in Tempo, with exact SF Symbol name, variant, weight, color token, and context.

#### Tab Bar Icons (5 tabs)

| Tab | SF Symbol (Selected) | SF Symbol (Unselected) | Label | Weight Selected | Weight Unselected | Color Selected | Color Unselected |
|-----|---------------------|----------------------|-------|-----------------|-------------------|----------------|-----------------|
| Dashboard | `square.grid.2x2.fill` | `square.grid.2x2` | Command | Bold | Regular | `tempo.color.primary.signal` | `tempo.color.secondary.concrete` |
| Training | `flame.fill` | `flame` | Train | Bold | Regular | `tempo.color.primary.signal` | `tempo.color.secondary.concrete` |
| Recovery | `heart.circle.fill` | `heart.circle` | Recover | Bold | Regular | `tempo.color.primary.signal` | `tempo.color.secondary.concrete` |
| Study | `book.fill` | `book` | Study | Bold | Regular | `tempo.color.primary.signal` | `tempo.color.secondary.concrete` |
| Profile | `person.fill` | `person` | Profile | Bold | Regular | `tempo.color.primary.signal` | `tempo.color.secondary.concrete` |

#### Navigation Icons

| Icon | SF Symbol | Variant | Weight | Size | Color Token | Context |
|------|-----------|---------|--------|------|-------------|---------|
| Back | `chevron.left` | Outline | Regular | 22pt | `tempo.color.primary.signal` | Navigation back button |
| Close | `xmark` | Outline | Regular | 22pt | `tempo.color.text.primary` | Dismiss modal/sheet |
| Settings | `gearshape.fill` | Filled | Regular | 22pt | `tempo.color.text.primary` | Settings access from profile |
| Notifications | `bell.fill` | Filled | Regular | 22pt | `tempo.color.text.primary` | Notification center from dashboard |
| Share | `square.and.arrow.up` | Outline | Regular | 22pt | `tempo.color.primary.signal` | Share workout/achievement |
| Edit | `pencil` | Outline | Regular | 22pt | `tempo.color.primary.signal` | Enter edit mode |
| Done | `checkmark` | Outline | Semibold | 22pt | `tempo.color.primary.signal` | Confirm edit/action |
| More | `ellipsis` | Outline | Regular | 22pt | `tempo.color.text.primary` | Overflow menu |
| Filter | `line.3.horizontal.decrease` | Outline | Regular | 22pt | `tempo.color.text.primary` | Filter/sort content |
| Search | `magnifyingglass` | Outline | Regular | 16pt | `tempo.color.secondary.concrete` | Search bar leading icon |
| Calendar | `calendar` | Outline | Regular | 22pt | `tempo.color.primary.signal` | Date picker trigger |

#### Action Icons

| Icon | SF Symbol | Variant | Weight | Size | Color Token | Context |
|------|-----------|---------|--------|------|-------------|---------|
| Add/Create | `plus` | Outline | Medium | 24pt (FAB), 22pt (nav) | `tempo.color.text.inverse` (FAB), `tempo.color.primary.signal` (nav) | Add new item |
| Start | `play.fill` | Filled | Medium | 28pt | `tempo.color.text.inverse` on colored bg | Start timer/workout |
| Pause | `pause.fill` | Filled | Medium | 28pt | `tempo.color.text.inverse` on colored bg | Pause timer |
| Stop | `stop.fill` | Filled | Medium | 28pt | `tempo.color.semantic.error` | Stop/end session |
| Log | `square.and.pencil` | Outline | Medium | 28pt | `tempo.color.primary.signal` | Quick log action |
| Camera | `camera.fill` | Filled | Medium | 28pt | `tempo.color.primary.signal` | Photo-to-log (meal photo) |
| Scan | `barcode.viewfinder` | Outline | Medium | 28pt | `tempo.color.primary.signal` | Barcode scan (food) |
| Delete | `trash.fill` | Filled | Medium | 22pt | `tempo.color.semantic.error` | Delete item (destructive) |
| Refresh | `arrow.clockwise` | Outline | Medium | 22pt | `tempo.color.primary.signal` | Refresh/sync data |
| Undo | `arrow.uturn.backward` | Outline | Medium | 22pt | `tempo.color.primary.signal` | Undo last action |
| Skip | `forward.fill` | Filled | Medium | 22pt | `tempo.color.secondary.concrete` | Skip rest timer, skip Pomodoro |

#### Status Icons

| Icon | SF Symbol | Variant | Weight | Size | Color Token | Context |
|------|-----------|---------|--------|------|-------------|---------|
| Task complete | `checkmark.circle.fill` | Filled | Bold | 20pt | `tempo.color.semantic.success` | Task done, target met |
| Task incomplete | `circle` | Outline | Regular | 20pt | `tempo.color.border.default` | Unchecked task |
| Warning | `exclamationmark.triangle.fill` | Filled | Semibold | 20pt (inline), 48pt (full-screen error) | `tempo.color.semantic.warning` | Warning state |
| Error | `xmark.circle.fill` | Filled | Bold | 20pt | `tempo.color.semantic.error` | Error/failed state |
| Info | `info.circle.fill` | Filled | Regular | 20pt | `tempo.color.semantic.info` | Information tooltip |
| Lock | `lock.fill` | Filled | Medium | 20pt (inline), 28pt (locked achievement) | `tempo.color.secondary.concrete` | Locked feature |
| Streak fire | `flame.fill` | Filled | Bold | 16pt | `tempo.color.primary.signal` | Active streak |
| Streak broken | `flame` | Outline | Regular | 16pt | `tempo.color.semantic.error` | Broken streak |
| Trending up | `arrow.up.right` | Outline | Semibold | 14pt | `tempo.color.semantic.success` | Positive trend |
| Trending down | `arrow.down.right` | Outline | Semibold | 14pt | `tempo.color.semantic.error` | Negative trend |
| Stable | `arrow.right` | Outline | Semibold | 14pt | `tempo.color.secondary.concrete` | No change |

#### Training Module Icons

| Icon | SF Symbol | Variant | Weight | Size | Color Token | Context |
|------|-----------|---------|--------|------|-------------|---------|
| Dumbbell | `dumbbell.fill` | Filled | Semibold | 24pt | `tempo.color.primary.signal` | Strength training type |
| Running | `figure.run` | Filled | Medium | 24pt | `tempo.color.primary.signal` | Cardio/running type |
| Cycling | `figure.outdoor.cycle` | Filled | Medium | 24pt | `tempo.color.primary.signal` | Cycling type |
| Swimming | `figure.pool.swim` | Filled | Medium | 24pt | `tempo.color.primary.signal` | Swimming type |
| HIIT | `bolt.heart.fill` | Filled | Semibold | 24pt | `tempo.color.primary.signal` | HIIT type |
| Yoga | `figure.yoga` | Filled | Medium | 24pt | `tempo.color.primary.signal` | Yoga/flexibility |
| Rest day | `bed.double.fill` | Filled | Medium | 24pt | `tempo.color.accent.violet` | Scheduled rest |
| PR/Record | `trophy.fill` | Filled | Bold | 28pt | `tempo.color.accent.amber` | Personal record celebration |
| Weight | `scalemass.fill` | Filled | Medium | 20pt | `tempo.color.text.secondary` | Body weight tracking |
| Rep counter | `number.circle.fill` | Filled | Semibold | 20pt | `tempo.color.text.primary` | Reps display |
| Timer | `timer` | Outline | Medium | 20pt | `tempo.color.primary.signal` | Set rest timer |
| Muscle group | `figure.strengthtraining.traditional` | Filled | Medium | 28pt | `tempo.color.primary.signal` | Exercise targeting |

#### Recovery Module Icons

| Icon | SF Symbol | Variant | Weight | Size | Color Token | Context |
|------|-----------|---------|--------|------|-------------|---------|
| Heart rate | `heart.fill` | Filled | Semibold | 20pt | `tempo.color.accent.violet` | Resting HR metric |
| HRV | `waveform.path.ecg` | Outline | Medium | 20pt | `tempo.color.accent.violet` | HRV metric |
| Sleep | `moon.fill` | Filled | Semibold | 20pt | `tempo.color.accent.violet` | Sleep data |
| Recovery score | `gauge.with.needle.fill` | Filled | Semibold | 24pt | (zone color) | Overall recovery |
| Strain | `bolt.fill` | Filled | Semibold | 20pt | `tempo.color.accent.violet` | Strain/load |
| Temperature | `thermometer.medium` | Outline | Medium | 20pt | `tempo.color.accent.violet` | Skin temp |
| SpO2 | `lungs.fill` | Filled | Medium | 20pt | `tempo.color.accent.violet` | Blood oxygen |
| Readiness | `battery.100percent.bolt` | Filled | Medium | 20pt | (zone color) | Readiness indicator |

#### Study Module Icons

| Icon | SF Symbol | Variant | Weight | Size | Color Token | Context |
|------|-----------|---------|--------|------|-------------|---------|
| Book open | `book.fill` | Filled | Semibold | 24pt | `tempo.color.accent.electric` | Active study session |
| Pomodoro | `timer` | Outline | Medium | 20pt | `tempo.color.accent.electric` | Pomodoro timer |
| Notes | `note.text` | Outline | Medium | 20pt | `tempo.color.accent.electric` | Study notes |
| Exam | `doc.text.fill` | Filled | Medium | 20pt | `tempo.color.accent.electric` | Exam/test entry |
| Grade | `graduationcap.fill` | Filled | Semibold | 20pt | `tempo.color.accent.electric` | Grade tracking |
| Subject | `folder.fill` | Filled | Medium | 20pt | `tempo.color.accent.electric` | Subject/course |
| Focus | `eye.fill` | Filled | Semibold | 20pt | `tempo.color.accent.electric` | Focus mode active |
| Break | `cup.and.saucer.fill` | Filled | Medium | 20pt | `tempo.color.semantic.success` | Break timer (green = rest) |
| Flashcard | `rectangle.on.rectangle.angled` | Outline | Medium | 20pt | `tempo.color.accent.electric` | Flashcard review |
| Stats | `chart.bar.fill` | Filled | Medium | 20pt | `tempo.color.accent.electric` | Study statistics |

#### Nutrition Module Icons

| Icon | SF Symbol | Variant | Weight | Size | Color Token | Context |
|------|-----------|---------|--------|------|-------------|---------|
| Meal | `fork.knife` | Outline | Medium | 24pt | `tempo.color.semantic.success` | General meal entry |
| Breakfast | `sun.horizon.fill` | Filled | Medium | 20pt | `tempo.color.semantic.success` | Morning meal |
| Lunch | `sun.max.fill` | Filled | Medium | 20pt | `tempo.color.semantic.success` | Midday meal |
| Dinner | `moon.haze.fill` | Filled | Medium | 20pt | `tempo.color.semantic.success` | Evening meal |
| Snack | `carrot.fill` | Filled | Medium | 20pt | `tempo.color.semantic.success` | Snack entry |
| Water | `drop.fill` | Filled | Medium | 20pt | `tempo.color.accent.electric` | Water intake |
| Calories | `flame.fill` | Filled | Medium | 20pt | `tempo.color.accent.amber` | Calorie tracking (amber tint to distinguish from training) |
| Protein | `p.circle.fill` | Filled | Semibold | 16pt | `tempo.color.semantic.success` | Protein macro indicator |
| Carbs | `c.circle.fill` | Filled | Semibold | 16pt | `tempo.color.accent.electric` | Carb macro indicator |
| Fat | `f.circle.fill` | Filled | Semibold | 16pt | `tempo.color.accent.amber` | Fat macro indicator |
| Meal photo | `camera.fill` | Filled | Medium | 28pt | `tempo.color.semantic.success` | Photo-based logging |

#### Achievement / Badge Icons

| Icon | SF Symbol | Variant | Weight | Size | Color | Context |
|------|-----------|---------|--------|------|-------|---------|
| Bronze badge | `medal.fill` | Filled | Bold | 28pt | `#CD7F32` | Tier 1 achievement |
| Silver badge | `medal.fill` | Filled | Bold | 28pt | `#C0C0C0` | Tier 2 achievement |
| Gold badge | `medal.fill` | Filled | Bold | 28pt | `#FFD700` | Tier 3 achievement |
| Streak badge | `flame.fill` | Filled | Bold | 28pt | `#F59E0B` | Streak milestones |
| Level up | `arrow.up.circle.fill` | Filled | Bold | 32pt | Badge gradient color | Level increase |
| XP gain | `star.fill` | Filled | Semibold | 10pt | `#F59E0B` | XP reward in badge |
| Challenge won | `trophy.fill` | Filled | Bold | 28pt | `#FFD700` | Challenge victory |
| First blood | `1.circle.fill` | Filled | Bold | 28pt | `#C0C0C0` | First completion |

---

## 8. Component Library

### 8.1 Buttons

#### Primary Button

| Property | Value |
|----------|-------|
| **Height** | 52pt |
| **Corner radius** | 14pt (`tempo.radius.2xl`) |
| **Background** | `Signal Red` (#E63946) |
| **Text** | `Bone White` (#F5F2ED), SF Pro Text Semibold 17pt |
| **Text alignment** | Center |
| **Horizontal padding** | 24pt |
| **Minimum width** | 120pt |
| **Full-width variant** | Stretches to fill container minus screen edge padding |
| **Shadow** | None |
| **Border** | None |

**State transitions:**

| State | Visual Change | Animation | Haptic |
|-------|--------------|-----------|--------|
| **Default → Pressed** | Background: #C1303B. Scale: 0.97x. | `Animation.easeOut(duration: 0.1)` / cubic-bezier(0, 0, 0.58, 1) 100ms | `UIImpactFeedbackGenerator(style: .medium).impactOccurred()` |
| **Pressed → Released** | Background: #E63946. Scale: 1.0x. | `Animation.spring(response: 0.3, dampingFraction: 0.8)` 200ms | None |
| **Default → Disabled** | Background: #E5E7EB. Text: #9CA3AF. Opacity: 1.0 (not dimmed — color change only). | `Animation.easeInOut(duration: 0.2)` | None |
| **Default → Loading** | Background: Signal Red at 70% opacity. Text replaced by centered 20pt `ProgressView()` in white. | Text fades out 150ms, spinner fades in 150ms, sequenced | None |

**SwiftUI skeleton:**
```swift
Button(action: action) {
    Text(title)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(Color.Tempo.bone)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(isDisabled ? Color.Tempo.borderDefault : Color.Tempo.signal)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
}
.buttonStyle(.plain)
.scaleEffect(isPressed ? 0.97 : 1.0)
.animation(.easeOut(duration: 0.1), value: isPressed)
.disabled(isDisabled)
// No opacity change on disabled — color change handles it
```

**Dark mode:** Background: `#FF4D5A`. Pressed: `#E63946`. Disabled bg: `#38383A`, text: `#52525B`.

---

#### Secondary Button

| Property | Value |
|----------|-------|
| **Height** | 52pt |
| **Corner radius** | 14pt |
| **Background** | Transparent |
| **Border** | 1.5pt `Ink Black` (#0D0D0D) |
| **Text** | `Ink Black` (#0D0D0D), SF Pro Text Semibold 17pt |

**State transitions:**

| State | Visual Change | Animation | Haptic |
|-------|--------------|-----------|--------|
| **Default → Pressed** | Background: `#0D0D0D` at 5%. Scale: 0.97x. | 100ms ease-out | `UIImpactFeedbackGenerator(style: .light)` |
| **Pressed → Released** | Background: transparent. Scale: 1.0x. | 200ms spring(0.3, 0.8) | None |
| **Default → Disabled** | Border: `#D1D5DB`. Text: `#9CA3AF`. | 200ms ease-in-out | None |

**Dark mode:** Border: `#F5F2ED`. Text: `#F5F2ED`. Pressed bg: `#F5F2ED` at 10%. Disabled border: `#48484A`, text: `#52525B`.

---

#### Destructive Button

| Property | Value |
|----------|-------|
| **Height** | 52pt |
| **Corner radius** | 14pt |
| **Background** | Transparent |
| **Border** | 1.5pt `Fail Red` (#DC2626) |
| **Text** | `Fail Red` (#DC2626), SF Pro Text Semibold 17pt |

**State transitions:**

| State | Visual Change | Animation | Haptic |
|-------|--------------|-----------|--------|
| **Default → Pressed** | Background: `#DC2626` at 10%. Scale: 0.97x. | 100ms ease-out | `UINotificationFeedbackGenerator().notificationOccurred(.warning)` |
| **Pressed → Released** | Background: transparent. Scale: 1.0x. | 200ms spring(0.3, 0.8) | None |
| **Default → Disabled** | Border: `#D1D5DB`. Text: `#9CA3AF`. | 200ms ease-in-out | None |

**Dark mode:** Border: `#F87171`. Text: `#F87171`. Pressed bg: `#F87171` at 15%.

---

#### Ghost Button

| Property | Value |
|----------|-------|
| **Height** | 44pt |
| **Corner radius** | 10pt |
| **Background** | Transparent |
| **Border** | None |
| **Text** | `Signal Red` (#E63946), SF Pro Text Semibold 15pt |

**State transitions:**

| State | Visual Change | Animation | Haptic |
|-------|--------------|-----------|--------|
| **Default → Pressed** | Background: `#E63946` at 8%. | 100ms ease-out | `UIImpactFeedbackGenerator(style: .light)` |
| **Pressed → Released** | Background: transparent. | 150ms ease-out | None |
| **Default → Disabled** | Text: `#9CA3AF`. | 200ms ease-in-out | None |

**Dark mode:** Text: `#FF4D5A`. Pressed bg: `#FF4D5A` at 12%.

---

#### Icon-Only Button

| Property | Value |
|----------|-------|
| **Size** | 44x44pt (touch target), icon 22pt centered |
| **Corner radius** | 12pt |
| **Background** | Transparent |
| **Icon color** | `Ink Black` (#0D0D0D) default |

**State transitions:**

| State | Visual Change | Animation | Haptic |
|-------|--------------|-----------|--------|
| **Default → Pressed** | Background: `#0D0D0D` at 8%. | 80ms ease-out | `UIImpactFeedbackGenerator(style: .light)` |
| **Pressed → Released** | Background: transparent. | 150ms ease-out | None |
| **Default → Disabled** | Icon: `#9CA3AF`. | 200ms ease-in-out | None |

**Dark mode:** Icon: `#F5F2ED`. Pressed bg: `#F5F2ED` at 12%.

---

#### Floating Action Button (FAB)

| Property | Value |
|----------|-------|
| **Size** | 56x56pt |
| **Corner radius** | 28pt (circle) |
| **Background** | `Signal Red` (#E63946) |
| **Icon** | `plus`, 24pt, `Bone White`, Medium weight |
| **Shadow** | Elevation 3: `rgba(13, 13, 13, 0.20)`, X: 0, Y: 4pt, Blur: 12pt |
| **Position** | 20pt from trailing edge, 20pt above tab bar top edge |

**State transitions:**

| State | Visual Change | Animation | Haptic |
|-------|--------------|-----------|--------|
| **Default → Pressed** | Background: #C1303B. Scale: 0.92x. Shadow blur: 16pt. | 120ms ease-out | `UIImpactFeedbackGenerator(style: .medium)` |
| **Pressed → Released** | Background: #E63946. Scale: 1.0x. Shadow blur: 12pt. | Spring Loose `spring(response: 0.5, dampingFraction: 0.7)` | None |
| **Appear** | Scale 0 → 1.0 | Spring Loose `spring(response: 0.5, dampingFraction: 0.7)` | None |
| **Disappear (scroll down)** | Scale 1.0 → 0 + fade out | 200ms ease-in | None |

**Dark mode:** Background: `#FF4D5A`. Shadow: `rgba(0, 0, 0, 0.40)`.

**SwiftUI skeleton:**
```swift
Button(action: action) {
    Image(systemName: "plus")
        .font(.system(size: 24, weight: .medium))
        .foregroundStyle(Color.Tempo.bone)
        .frame(width: 56, height: 56)
        .background(Color.Tempo.signal)
        .clipShape(Circle())
        .shadow(color: Color.Tempo.ink.opacity(0.20), radius: 6, x: 0, y: 4)
}
.buttonStyle(.plain)
.scaleEffect(isPressed ? 0.92 : 1.0)
.animation(.easeOut(duration: 0.12), value: isPressed)
```

---

### 8.2 Cards

#### Standard Card

| Property | Value |
|----------|-------|
| **Background** | `#FFFFFF` (light) / `#1C1C1E` (dark) |
| **Corner radius** | 16pt (`tempo.radius.3xl`), continuous curve |
| **Padding** | 16pt all sides |
| **Shadow (light)** | Elevation 2: `rgba(13, 13, 13, 0.06)`, X: 0, Y: 2pt, Blur: 8pt |
| **Shadow (dark)** | None (border instead) |
| **Border (light)** | None |
| **Border (dark)** | 0.5pt `#38383A` |
| **Between cards** | 12pt vertical gap |

**SwiftUI skeleton:**
```swift
VStack(alignment: .leading, spacing: 12) {
    // Card content
}
.padding(16)
.background(Color.Tempo.surfaceCard)
.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
.shadow(color: Color.Tempo.ink.opacity(colorScheme == .dark ? 0 : 0.06), radius: 4, x: 0, y: 2)
.overlay(
    RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(Color.Tempo.borderDefault, lineWidth: 0.5)
        .opacity(colorScheme == .dark ? 1 : 0)
)
```

**Tap state:** Scale 0.97x, background dims 3%, 150ms spring. Haptic: `.light` impact.

---

#### Dashboard Quadrant Card

| Property | Value |
|----------|-------|
| **Layout** | 2x2 grid within screen margins |
| **Size** | `(screenWidth - 20pt - 20pt - 12pt) / 2` = card width. Height = card width (1:1 square). |
| **Corner radius** | 16pt, continuous |
| **Padding** | 12pt all sides |
| **Background** | `#FFFFFF` (light) / `#1C1C1E` (dark) |
| **Shadow** | Same as Standard Card |
| **Content layout** | Top-left: module icon (20pt, Semibold) + label (Caption 1). Center: primary metric (Data Large). Bottom: secondary metric or mini-chart. |
| **Module tint bar** | Top edge: 3pt height bar, full width, matches card top corner radius. Colors: Training = `Signal Red`, Recovery = `Protocol Violet`, Study = `Electric Blue`, Nutrition = `Mission Green` |

**Tap state:** Scale 0.96x, 150ms spring(0.3, 0.8). Haptic: `.light` impact.

**SwiftUI skeleton** (requires `@Environment(\.colorScheme) private var colorScheme`)**:**
```swift
VStack(alignment: .leading, spacing: 8) {
    HStack(spacing: 6) {
        Image(systemName: moduleIcon)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(moduleColor)
        Text(moduleLabel)
            .font(.caption)
            .foregroundStyle(Color.Tempo.textTertiary)
    }
    Spacer()
    Text(metricValue)
        .font(.system(size: 24, weight: .bold, design: .monospaced))
        .foregroundStyle(Color.Tempo.textPrimary)
    Text(secondaryMetric)
        .font(.caption2)
        .foregroundStyle(Color.Tempo.textSecondary)
}
.padding(12)
.frame(width: cardWidth, height: cardWidth)
.background(
    ZStack(alignment: .top) {
        Color.Tempo.surfaceCard
        VStack(spacing: 0) {
            moduleColor.frame(height: 3)
            Spacer()
        }
    }
)
.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
.shadow(color: Color.Tempo.ink.opacity(colorScheme == .dark ? 0 : 0.06), radius: 4, x: 0, y: 2)
.overlay(
    RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(Color.Tempo.borderDefault, lineWidth: 0.5)
        .opacity(colorScheme == .dark ? 1 : 0)
)
.scaleEffect(isPressed ? 0.96 : 1.0)
.animation(.spring(response: 0.3, dampingFraction: 0.8), value: isPressed)
```

---

#### Stat Card

| Property | Value |
|----------|-------|
| **Height** | 80pt |
| **Corner radius** | 12pt |
| **Padding** | 12pt all sides |
| **Background** | `#FFFFFF` (light) / `#1C1C1E` (dark) |
| **Layout** | Leading: label (Caption 1, secondary text) stacked above value (Data Large, primary text). Trailing: trend arrow icon (14pt, Semibold) with percentage (Caption 1, semantic color). |
| **Shadow** | Elevation stat: `rgba(13, 13, 13, 0.04)`, X: 0, Y: 1pt, Blur: 4pt |

---

#### Workout Card

| Property | Value |
|----------|-------|
| **Height** | Auto (content-driven), minimum 120pt |
| **Corner radius** | 16pt |
| **Padding** | 16pt all sides |
| **Background** | `#FFFFFF` (light) / `#1C1C1E` (dark) |
| **Layout** | Top row: workout icon (24pt, `Signal Red`) + workout name (Headline) + duration (Caption 1, trailing). Middle: exercise count (Body, secondary text). Bottom row: muscle groups as tags. Optional: mini volume chart (48pt height). |
| **Left accent** | 4pt wide bar, full height, `Signal Red`, radius follows card radius on left side only |
| **Tap state** | Scale 0.97x, background dims 3%. Haptic: `.light` impact. |

---

#### Exercise Row Card

| Property | Value |
|----------|-------|
| **Height** | 72pt |
| **Corner radius** | 12pt |
| **Padding** | 12pt horizontal, 10pt vertical |
| **Background** | `#FFFFFF` (light) / `#1C1C1E` (dark) |
| **Layout** | Leading: exercise name (Headline). Below: target (Subheadline, secondary text, e.g., "4x8 @ 80kg"). Trailing: completion (Data Medium, colored — green done, primary in-progress, disabled not started). |
| **Swipe actions** | Trailing: Delete (Fail Red bg, trash.fill icon), Edit (gray bg, pencil icon). Leading: none. |

---

#### Achievement Card

| Property | Value |
|----------|-------|
| **Height** | 96pt |
| **Corner radius** | 16pt |
| **Padding** | 16pt all sides |
| **Background** | `#FFFFFF` (light) / `#1C1C1E` (dark) |
| **Layout** | Leading: badge icon (40pt circle, tier-based bg). Center: name (Headline) + description (Caption 1, secondary) + date (Caption 2, tertiary). Trailing: XP value (Data Medium, `Command Amber`). |
| **Locked state** | Entire card at 50% opacity. Badge: `lock.fill` replaces icon. Description replaced with requirement text. XP still visible. |
| **Unlock animation** | See [Section 10 — Micro-Interaction Choreography](#106-achievement-unlock). |

---

#### Prescription Card (Drill Sergeant Message)

| Property | Value |
|----------|-------|
| **Corner radius** | 16pt |
| **Padding** | 16pt all sides |
| **Background** | `Ink Black` (#0D0D0D) — BOTH modes |
| **Text** | `Bone White` (#F5F2ED) |
| **Layout** | Top: "DRILL SERGEANT" (Drill Label style: Caption 1 Bold, uppercase, `Command Amber`, letter-spacing +1.5pt). Below: message (Body Bold). Bottom-right: timestamp (Caption 2, `Ash`). |
| **Left accent** | 4pt wide bar, full height, `Signal Red` |
| **Border** | None |
| **Shadow** | Drill Sergeant glow: `rgba(230, 57, 70, 0.15)`, X: 0, Y: 0, Blur: 16pt |

---

### 8.3 Navigation

#### Tab Bar

| Property | Value |
|----------|-------|
| **Style** | Opaque background |
| **Background (light)** | `#FFFFFF` with thin 0.5pt top border `#E5E7EB` |
| **Background (dark)** | `#1C1C1E` with thin 0.5pt top border `#38383A` |
| **Blur** | None (opaque) |
| **Selected icon/label color** | `Signal Red` (#E63946) / dark: `#FF4D5A` |
| **Unselected icon/label color** | `Concrete` (#6B7280) / dark: `#8E8E93` |
| **Label font** | SF Pro Text Medium, 10pt |
| **Icon size** | 24pt SF Symbol point size |
| **5 tabs** | Command, Train, Recover, Study, Profile |

Tab switch animation and haptic: see [Section 10.1](#101-tab-switching).

---

#### Navigation Bar

| Property | Value |
|----------|-------|
| **Style** | Inline title (scrolls with content) by default. Large title for top-level screens only (Dashboard, Profile). |
| **Background (light)** | Transparent at top. When scrolled: `#FFFFFF` at 92% opacity + UIBlurEffect `.systemUltraThinMaterial` |
| **Background (dark)** | Transparent at top. When scrolled: `#1C1C1E` at 92% opacity + blur |
| **Title font** | Large: SF Pro Display Bold 34pt. Inline: SF Pro Text Semibold 17pt. |
| **Tint color** | `Signal Red` (#E63946) for back button and action items |
| **Separator** | 0.5pt `#E5E7EB` (light) / `#38383A` (dark), visible only when content scrolls beneath |

---

#### Segmented Control

| Property | Value |
|----------|-------|
| **Height** | 36pt |
| **Corner radius** | 8pt (container), 6pt (selected indicator) |
| **Background** | `#E5E2DC` (light) / `#262626` (dark) |
| **Selected segment bg** | `#FFFFFF` (light) / `#3A3A3C` (dark) |
| **Selected text** | Ink Black / Bone White, SF Pro Text Semibold 13pt |
| **Unselected text** | Concrete / `#8E8E93`, SF Pro Text Regular 13pt |
| **Shadow on selected** | `rgba(13, 13, 13, 0.08)`, Y: 1pt, Blur: 3pt |
| **Animation** | Selected indicator slides: `spring(response: 0.25, dampingFraction: 0.8)` |
| **Haptic** | `.selection` on segment change |

---

#### Bottom Sheet

| Property | Value |
|----------|-------|
| **Corner radius** | 20pt (top-left, top-right only) |
| **Background** | `#FFFFFF` (light) / `#2C2C2E` (dark) |
| **Grabber** | 36pt wide, 5pt tall, corner radius 2.5pt, `#D1D5DB` (light) / `#48484A` (dark), centered, 8pt from top |
| **Shadow** | Elevation 3: `rgba(13, 13, 13, 0.15)`, Y: -4pt, Blur: 20pt |
| **Detents** | `.medium` (50% screen height), `.large` (92% screen height) |
| **Padding** | 20pt horizontal, 16pt below grabber, safe area bottom |
| **Scrim** | `rgba(13, 13, 13, 0.40)` (light) / `rgba(0, 0, 0, 0.50)` (dark) |
| **Animation** | System `UISheetPresentationController` |
| **Haptic** | `.light` impact on detent snap |

---

### 8.4 Lists

#### Standard Row

| Property | Value |
|----------|-------|
| **Height** | 56pt minimum (expands with Dynamic Type) |
| **Padding** | 16pt leading, 16pt trailing, 12pt vertical |
| **Background** | `#FFFFFF` (light) / `#1C1C1E` (dark) |
| **Title** | Headline (17pt Semibold), primary text color |
| **Subtitle** | Subheadline (15pt Regular), secondary text color |
| **Accessory** | `chevron.right` 14pt Regular, `Ash` color, or custom trailing content |
| **Divider** | 0.5pt `#E5E7EB` / `#38383A`, inset 16pt from leading |
| **Pressed state** | Background: `#F3F4F6` (light) / `#2C2C2E` (dark), 80ms highlight delay |

#### Exercise Row

| Property | Value |
|----------|-------|
| **Height** | 72pt |
| **Padding** | 16pt horizontal, 12pt vertical |
| **Layout** | Leading: exercise icon or muscle group icon (28pt, `Signal Red`). Column: exercise name (Headline) + last performance (Caption 1, tertiary, e.g., "Last: 4x8 @ 80kg"). Trailing: current target (Data Medium). |
| **Divider** | 0.5pt, inset 56pt from leading (past icon area) |
| **Reorderable** | Drag handle `line.3.horizontal` appears in edit mode, 8pt from trailing |

#### Meal Row

| Property | Value |
|----------|-------|
| **Height** | 80pt |
| **Padding** | 16pt horizontal, 12pt vertical |
| **Layout** | Leading: meal photo (56x56pt, corner radius 8pt) or meal type icon (28pt, `Mission Green`). Column: meal name (Headline) + time (Caption 1, tertiary). Trailing: calories (Data Medium) + macro split bar (48pt wide, 4pt tall, 3-segment bar P/C/F in green/blue/amber). |
| **Divider** | 0.5pt, inset 88pt (past photo area) |

---

### 8.5 Inputs

#### Text Field

| Property | Value |
|----------|-------|
| **Height** | 48pt |
| **Corner radius** | 12pt |
| **Background** | `#F3F4F6` (light) / `#262626` (dark) |
| **Border default** | 1pt `#E5E7EB` (light) / `#38383A` (dark) |
| **Border focused** | 2pt `Ink Black` (#0D0D0D) / `Bone White` (#F5F2ED) |
| **Border error** | 2pt `Fail Red` (#DC2626) / `#F87171` |
| **Padding** | 12pt horizontal, 12pt vertical |
| **Text** | Body (17pt Regular), primary text color |
| **Placeholder** | Body (17pt Regular), `#9CA3AF` / `#52525B` |
| **Label** | Caption 1 (12pt Regular), secondary text color, 8pt above field |
| **Helper text** | Footnote (13pt Regular), tertiary text, 4pt below |
| **Error text** | Footnote (13pt Regular), `Fail Red`, 4pt below |
| **Clear button** | `xmark.circle.fill` 18pt, `Ash`, appears when field has text and is focused |
| **Leading icon** | Optional, 20pt, `Concrete`, 12pt from leading edge |

**Focus animation:** Border width 1pt → 2pt, color transitions to focused color. Duration: 200ms ease-in-out.

---

#### Number Stepper

| Property | Value |
|----------|-------|
| **Height** | 44pt |
| **Layout** | Minus button (44x44pt) + value (min 60pt wide, centered) + plus button (44x44pt) |
| **Button style** | Circle, 36pt diameter, background `#F3F4F6` / `#262626`, icon `minus`/`plus` 16pt |
| **Value display** | Data Medium (17pt Mono Semibold), primary text |
| **Long press** | Continuous increment/decrement. 300ms initial delay, then 100ms interval, accelerating to 50ms after 2s |
| **Haptic** | `.light` impact on each step |

---

#### Toggle

| Property | Value |
|----------|-------|
| **Size** | 51x31pt (iOS standard) |
| **On color** | `Signal Red` (#E63946) / `#FF4D5A` |
| **Off color** | `#E5E7EB` / `#38383A` |
| **Thumb** | White circle, system standard |
| **Animation** | System standard (250ms spring) |
| **Haptic** | `.light` impact on toggle |

---

### 8.6 Progress Indicators

#### Linear Progress Bar

| Property | Value |
|----------|-------|
| **Track height** | 6pt (default), 4pt (compact), 8pt (large) |
| **Corner radius** | Half of height (fully rounded) |
| **Track background** | `#E5E7EB` (light) / `#38383A` (dark) |
| **Fill color** | Context-dependent: `Signal Red` (default), `Mission Green` (nutrition), `Electric Blue` (study), `Command Amber` (XP) |
| **Fill animation** | `spring(response: 0.6, dampingFraction: 0.8)`, animates from 0 or previous value |
| **Overfill (>100%)** | Fill color: `Mission Green`. Pulse: scale 1.0 → 1.02 → 1.0, 1s infinite loop. |

#### Circular Progress Ring

| Property | Value |
|----------|-------|
| **Sizes** | Small: 40pt, Medium: 64pt, Large: 120pt, XL: 200pt |
| **Stroke width** | Small: 4pt, Medium: 6pt, Large: 8pt, XL: 12pt |
| **Track color** | `#E5E7EB` (light) / `#38383A` (dark) |
| **Fill** | Gradient (see gradient definitions). Clockwise from 12 o'clock. |
| **End cap** | Round (`.round` line cap) |
| **Center content** | Value in Data/Score style, centered. Optional label below in Caption 2. |
| **Draw animation** | Trim from 0 to target, ease-out cubic-bezier(0, 0, 0.58, 1), 800ms |
| **Haptic** | `.success` notification when ring reaches 100% |

#### Score Ring (Activity Ring Style)

| Property | Value |
|----------|-------|
| **Size** | 200pt (dashboard), 120pt (module detail) |
| **Ring count** | Up to 3 concentric rings |
| **Ring gap** | 4pt between rings |
| **Ring stroke** | 12pt (outer), 10pt (middle), 8pt (inner) |
| **Ring colors** | Outer: `Signal Red`, Middle: `Protocol Violet`, Inner: `Electric Blue` |
| **Track opacity** | 20% of ring color |
| **Overshoot** | Ring wraps past start with overlap shadow |
| **Center** | Score Display font, label below (Caption 1) |
| **Stagger animation** | Each ring draws sequentially, 150ms delay between them, ease-out, 700ms per ring |

#### Streak Dots

| Property | Value |
|----------|-------|
| **Dot size** | 8pt diameter |
| **Dot gap** | 4pt |
| **Active dot** | `Signal Red` filled |
| **Future dot** | `#E5E7EB` (light) / `#38383A` (dark) filled |
| **Missed dot** | `Fail Red` filled with 1pt border (`#FFFFFF` light / `#1C1C1E` dark) |
| **Today dot** | `Signal Red` with pulsing ring: opacity 0.3 → 0.0, scale 1.0 → 1.4, 2s infinite loop |
| **Layout** | 7 dots (weekly), 30 dots wrapped in 7-column rows (monthly) |

---

### 8.7 Charts

#### Line Chart

| Property | Value |
|----------|-------|
| **Height** | 200pt (standard), 120pt (in-card compact) |
| **Line width** | 2pt |
| **Line color** | Context primary color |
| **Area fill** | Gradient: line color at 20% opacity → transparent |
| **Data points** | 6pt circle, filled with line color, 2pt border (`#FFFFFF` light / `#1C1C1E` dark) |
| **Selected point** | Scale 1.5x. Tooltip: corner radius 8pt, padding 8pt 12pt, `Ink Black` bg, Data Small value + Caption 2 label in `Bone White` |
| **Grid lines** | Horizontal only, 0.5pt, `#E5E7EB` / `#38383A`, dashed (4pt on, 4pt off) |
| **Axis labels** | Caption 2, tertiary text. Y on leading, X on bottom. |
| **Draw animation** | Line left-to-right 800ms ease-out. Fill fades in 200ms after. Points pop in 50ms stagger. |
| **Zero line** | If data crosses zero: 1pt solid `#D1D5DB` at y=0 |

#### Bar Chart

| Property | Value |
|----------|-------|
| **Height** | 200pt |
| **Bar width** | Flexible, min 16pt, max 40pt. Gap: 8pt. |
| **Corner radius** | Top corners only: 4pt (narrow), 6pt (wide) |
| **Bar color** | Context primary, or multi-color for stacked (P green, C blue, F amber) |
| **Selected bar** | All other bars dim to 40% opacity. Tooltip above. |
| **Draw animation** | Bars grow from baseline, staggered 50ms per bar, 400ms each, spring |

#### Heatmap Calendar

| Property | Value |
|----------|-------|
| **Cell size** | 14pt square |
| **Cell gap** | 2pt |
| **Cell corner radius** | 3pt |
| **Intensity (light)** | 5 levels: empty `#E5E7EB`, 25% `#FCA5A5`, 50% `#F87171`, 75% `#EF4444`, 100% `#DC2626` |
| **Intensity (dark)** | 5 levels: empty `#38383A`, 25% `#7F1D1D`, 50% `#991B1B`, 75% `#B91C1C`, 100% `#DC2626` |
| **Layout** | 7 rows (Mon-Sun) x N weeks. Day labels leading (Caption 2, tertiary). Month labels top (Caption 1, secondary). |
| **Today** | 1.5pt border in `Ink Black` / `Bone White` |
| **Tap** | Tooltip with date + value |
| **Draw animation** | Cells fade in row by row, 20ms stagger per cell |

#### Radar Chart

| Property | Value |
|----------|-------|
| **Size** | 200x200pt |
| **Axes** | 5-6 (Strength, Endurance, Recovery, Nutrition, Study, Consistency) |
| **Web rings** | 3-5 concentric, 0.5pt, `#E5E7EB` / `#38383A` |
| **Axis lines** | 0.5pt, `#D1D5DB` / `#48484A` |
| **Data fill** | `Signal Red` at 15%, 2pt `Signal Red` border |
| **Data points** | 6pt circles, `Signal Red` filled, 2pt border (`#FFFFFF` light / `#1C1C1E` dark) |
| **Labels** | Caption 1, secondary text, 12pt outside outer ring |
| **Morph animation** | Center → actual shape, 600ms spring |
| **Comparison** | Optional second dataset: `Electric Blue` at 10%, 1.5pt dashed border |

---

### 8.8 Alerts & Notifications

#### Toast Notification

| Property | Value |
|----------|-------|
| **Width** | Screen width - 40pt (20pt each side) |
| **Height** | Auto, min 48pt |
| **Corner radius** | 14pt |
| **Background** | `Ink Black` at 95% / `#2C2C2E` at 95% |
| **Text** | `Bone White`, Body (17pt) |
| **Leading icon** | 20pt, semantic color |
| **Position** | Top, 8pt below safe area |
| **Entry** | Slides down from above safe area, `spring(response: 0.3, dampingFraction: 0.7)` |
| **Exit** | Slides up + fades out, 200ms ease-in |
| **Duration** | 3s auto-dismiss. Swipe up to dismiss early. |
| **Haptic** | Success: `.success`, Warning: `.warning`, Error: `.error` notification |

#### Banner

| Property | Value |
|----------|-------|
| **Width** | Full screen width |
| **Height** | Auto, min 56pt |
| **Padding** | 16pt horizontal, 12pt vertical |
| **Background** | Semantic tint: error `#FEF2F2`, warning `#FEFCE8`, success `#F0FDF4`, info `#EFF6FF` |
| **Left accent** | 4pt vertical bar, full semantic color |
| **Text** | Body, primary text. Optional action link: Body Bold, `Signal Red`. |
| **Leading icon** | 20pt, semantic color |
| **Dismiss** | Trailing `xmark` button (44x44pt) |
| **Position** | Below navigation bar, pushes content down |
| **Animation** | Height expand from 0 + content fade-in, 300ms ease-in-out |
| **Dark mode backgrounds** | Error: `#450A0A`, Warning: `#422006`, Success: `#052E16`, Info: `#172554` |

#### Modal Alert

| Property | Value |
|----------|-------|
| **Width** | Screen width - 48pt |
| **Corner radius** | 20pt |
| **Background** | `#FFFFFF` (light) / `#2C2C2E` (dark) |
| **Padding** | 24pt top, 20pt horizontal, 16pt bottom |
| **Title** | Title 3 (20pt Semibold), center-aligned |
| **Message** | Body, secondary text, center-aligned, 8pt below title |
| **Button stack** | Vertical, 16pt below message. Primary (full width) + Ghost secondary (full width). 8pt gap. |
| **Scrim** | `rgba(13, 13, 13, 0.40)` / `rgba(0, 0, 0, 0.50)` |
| **Entry** | Scale 0.9 → 1.0 + fade in, 250ms `spring(response: 0.3, dampingFraction: 0.8)`. Scrim fades 200ms. |
| **Exit** | Scale → 0.95 + fade out, 150ms ease-in. Scrim fades 200ms. |
| **Haptic** | `.warning` notification on appear |

#### Drill Sergeant Alert (Signature)

Tempo's signature alert — accountability callouts, missed targets, motivational orders.

| Property | Value |
|----------|-------|
| **Width** | Screen width - 32pt |
| **Corner radius** | 20pt |
| **Background** | `Ink Black` (#0D0D0D) — BOTH modes |
| **Border** | 2pt `Signal Red` (#E63946) |
| **Padding** | 24pt all sides |
| **Header** | "ORDERS" in Orders Label style (Caption 1 Bold, uppercase, `Command Amber`, letter-spacing +2.0pt) |
| **Message** | Title 2 (22pt Bold), `Bone White`, left-aligned |
| **Detail** | Body (17pt Regular), `#A1A1AA`, 8pt below message |
| **Action button** | Primary Button, full width, 20pt below detail |
| **Dismiss** | Ghost button "Dismiss" below action, or swipe down |
| **Shadow** | Drill glow: `rgba(230, 57, 70, 0.20)`, X: 0, Y: 0, Blur: 24pt |
| **Entry** | Slides up from bottom, `spring(response: 0.5, dampingFraction: 0.65)`. Red border pulses once (opacity 1.0 → 0.5 → 1.0, 400ms). |
| **Haptic** | Three rapid `.heavy` impacts, 100ms apart (warning siren pattern) |

---

### 8.9 Badges

#### XP Badge

| Property | Value |
|----------|-------|
| **Size** | 24pt height, width auto (content + 16pt horizontal padding) |
| **Corner radius** | 12pt (pill) |
| **Background** | `Command Amber` at 15% |
| **Text** | "+50 XP" in Caption 1 Bold, `Command Amber` |
| **Icon** | `star.fill` 10pt, `Command Amber`, 4pt before text |
| **Appear** | Scale 0 → 1.1 → 1.0 (bounce), 300ms. Float upward 8pt while fading in. |

#### Level Badge

| Property | Value |
|----------|-------|
| **Size** | 48x48pt |
| **Shape** | Circle |
| **Background** | Tier gradient: 1-10 `#6B7280`→`#4B5563`, 11-25 `#22C55E`→`#16A34A`, 26-50 `#3B82F6`→`#2563EB`, 51-75 `#8B5CF6`→`#7C3AED`, 76-100 `#F59E0B`→`#D97706` |
| **Text** | Level number, SF Pro Rounded Bold, sized to fit (18-22pt), `#FFFFFF` |
| **Border** | 2pt `#FFFFFF` (light) / `#0D0D0D` (dark) |
| **Shadow** | Badge gradient start color at 30%, Y: 2pt, Blur: 8pt |

#### Achievement Badge

| Property | Value |
|----------|-------|
| **Size** | 64x64pt (grid), 40x40pt (inline) |
| **Shape** | Circle |
| **Background** | Bronze `#CD7F32`, Silver `#C0C0C0`, Gold `#FFD700`, Platinum `#E5E4E2` |
| **Icon** | Centered SF Symbol, 28pt (64pt) / 18pt (40pt), `#FFFFFF` |
| **Border** | 2pt darker shade of background |
| **Locked** | Grayscale, 40% opacity, `lock.fill` replaces icon |
| **Shine** | Radial gradient: white 0% opacity center → white 15% at 30% radius → transparent at edge |

#### Recovery Zone Badge

| Property | Value |
|----------|-------|
| **Size** | 28pt height, pill shape |
| **Corner radius** | 14pt |
| **Background** | Zone color at 15% |
| **Text** | Zone label ("GREEN"/"YELLOW"/"RED"), Caption 1 Bold, zone color |
| **Leading dot** | 8pt filled circle, zone color, 6pt before text |

---

### 8.10 Timer Components

#### Pomodoro Timer Display

| Property | Value |
|----------|-------|
| **Size** | 280x280pt |
| **Outer ring** | 240pt diameter, 10pt stroke, `Electric Blue` gradient. Track: `#E5E7EB`/`#38383A`. Clockwise from 12 o'clock. |
| **Time display** | Center, Timer Display (SF Mono Bold 56pt), primary text |
| **Session label** | Below time, Zone Label style: Caption 1, "FOCUS" (`Electric Blue`) or "BREAK" (`Mission Green`), uppercase, +1.0pt spacing |
| **Session count** | Below label, Caption 2, "2 of 4", tertiary text |
| **Controls** | Below ring, 24pt gap: Play/Pause (56pt circle, `Electric Blue` bg, white icon), Skip (44pt circle, transparent, `Concrete` `forward.fill`) |
| **Complete** | Ring pulses 3x (scale 1.0 → 1.05, 300ms each). Haptic: `.success` |

#### Workout Rest Timer

| Property | Value |
|----------|-------|
| **Size** | Full-width card, 120pt height |
| **Background** | `Ink Black` — BOTH modes |
| **Corner radius** | 16pt |
| **Time** | Center, Timer Display Small (SF Mono Semibold 40pt), `Bone White` |
| **Label** | "REST" above time, Zone Label style, `Signal Red`, +1.5pt spacing |
| **Progress bar** | Full width minus 32pt padding, 4pt, `Signal Red` fill counting down |
| **Skip button** | Trailing Ghost button, "SKIP", `Signal Red` |
| **Expire** | Background flashes `Signal Red` → `Ink Black` 2x (200ms each). Text briefly turns `Command Amber`. Haptic: 3x `.heavy` 100ms apart. |

---

### 8.11 Empty States

| Property | Value |
|----------|-------|
| **Layout** | Vertically centered in available space |
| **Icon** | 48pt, Ultralight weight, `Ash` color |
| **Title** | Title 3 (20pt Semibold), primary text, 16pt below icon |
| **Message** | Body (17pt Regular), secondary text, center-aligned, 8pt below title, max 280pt width |
| **CTA** | Primary or Secondary button, 24pt below message |

**Drill sergeant copy for each module:**

| Module | Icon | Title + Message | CTA |
|--------|------|----------------|-----|
| Training | `dumbbell` | "No workouts logged. The iron is waiting." | "Start Training" |
| Meals | `fork.knife` | "Empty plate, empty gains. Log your fuel." | "Log Meal" |
| Study | `book` | "Books don't read themselves. Start a session." | "Study Now" |
| Friends | `person.2` | "Solo mission. Add your squad." | "Find Friends" |
| Challenges | `trophy` | "No challenges active. Time to compete." | "Browse Challenges" |
| Achievements | `medal` | "Nothing earned. Start working." | "View Targets" |
| Recovery | `heart.circle` | "No recovery data. Connect your Whoop." | "Connect Device" |

---

### 8.12 Segmented Picker

| Property | Value |
|----------|-------|
| **Height** | 36pt |
| **Corner radius (container)** | 8pt (`tempo.radius.md`) |
| **Corner radius (indicator)** | 6pt (`tempo.radius.sm`) |
| **Background** | `#E5E2DC` (light) / `#262626` (dark) |
| **Selected indicator bg** | `#FFFFFF` (light) / `#3A3A3C` (dark) |
| **Selected text** | Ink Black / Bone White, SF Pro Text Semibold 13pt |
| **Unselected text** | Concrete / `#8E8E93`, SF Pro Text Regular 13pt |
| **Indicator shadow** | `rgba(13, 13, 13, 0.08)`, Y: 1pt, Blur: 3pt (light only) |
| **Indicator slide animation** | `spring(response: 0.25, dampingFraction: 0.8)` — Spring Tight |
| **Haptic** | `UISelectionFeedbackGenerator().selectionChanged()` |
| **Minimum segment width** | 64pt |
| **Padding** | 2pt container inset (segment labels centered within available width) |

**SwiftUI skeleton:**
```swift
struct TempoSegmentedPicker<T: Hashable & CustomStringConvertible>: View {
    let options: [T]
    @Binding var selection: T
    @Namespace private var animation
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Text(option.description)
                    .font(.system(size: 13, weight: selection == option ? .semibold : .regular))
                    .foregroundStyle(
                        selection == option
                            ? Color.Tempo.textPrimary
                            : Color.Tempo.textTertiary
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background {
                        if selection == option {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.Tempo.surfaceCard)
                                .shadow(
                                    color: Color.Tempo.ink.opacity(colorScheme == .dark ? 0 : 0.08),
                                    radius: 1.5, x: 0, y: 1
                                )
                                .matchedGeometryEffect(id: "segment", in: animation)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            selection = option
                        }
                    }
            }
        }
        .padding(2)
        .background(Color.Tempo.bgTertiary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .sensoryFeedback(.selection, trigger: selection)
    }
}
```

---

### 8.13 Sheet & Modal Presentation

#### Bottom Sheet Presentation

| Property | Value |
|----------|-------|
| **Corner radius** | 20pt (top-left, top-right) — `tempo.radius.4xl` |
| **Background** | `#FFFFFF` (light) / `#2C2C2E` (dark) |
| **Grabber** | 36pt wide, 5pt tall, radius 2.5pt, `#D1D5DB` / `#48484A`, centered, 8pt from top |
| **Detents** | `.medium` (50%), `.large` (92%). Custom fractional detents allowed. |
| **Scrim** | `rgba(13, 13, 13, 0.40)` (light) / `rgba(0, 0, 0, 0.50)` (dark) |
| **Scrim interaction** | Tap to dismiss (configurable). Background content non-interactive. |
| **Padding** | 20pt horizontal, 16pt below grabber, safe area bottom (34pt) |
| **Corner curve** | `.continuous` (SwiftUI default for sheets) |
| **Scroll behavior** | Content scrolls within sheet. Sheet expands to `.large` on scroll up at `.medium`. |
| **Haptic** | `.light` impact on detent snap |

**SwiftUI skeleton:**
```swift
.sheet(isPresented: $showSheet) {
    SheetContent()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(20)
        .presentationBackground(Color.Tempo.surfaceSheet)
}
```

#### Full-Screen Modal

| Property | Value |
|----------|-------|
| **Transition** | Slides up from bottom, scrim fades in. 400ms Spring Loose. |
| **Corner radius** | 0pt (full screen) |
| **Background** | `#F5F2ED` (light) / `#0D0D0D` (dark) — matches app background |
| **Close button** | Top-trailing, `xmark` 22pt in 44x44pt touch target |
| **Dismissal** | Close button or swipe down (interactive). |

**SwiftUI skeleton:**
```swift
.fullScreenCover(isPresented: $showModal) {
    NavigationStack {
        ModalContent()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showModal = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color.Tempo.textPrimary)
                            .frame(width: 44, height: 44)
                    }
                }
            }
    }
}
```

#### Confirmation Dialog (Action Sheet)

| Property | Value |
|----------|-------|
| **Style** | System `confirmationDialog` — follows iOS native presentation |
| **Background** | System blur material (light) / system dark material (dark) |
| **Button tint** | `Signal Red` for destructive, `Electric Blue` for standard actions |
| **Cancel** | Always present as separate grouped button at bottom |

```swift
.confirmationDialog("Delete workout?", isPresented: $showConfirm, titleVisibility: .visible) {
    Button("Delete", role: .destructive) { /* ... */ }
    Button("Cancel", role: .cancel) { }
} message: {
    Text("This cannot be undone.")
}
```

---

### 8.14 Toolbar Styling

| Property | Value |
|----------|-------|
| **Background (rest)** | Transparent — content visible through |
| **Background (scrolled)** | System material blur + tint: `#FFFFFF` at 92% (light) / `#1C1C1E` at 92% (dark) |
| **Separator** | 0.5pt `#E5E7EB` / `#38383A`, visible only when scrolled beneath |
| **Tint color** | `Signal Red` for primary actions, `Ink Black`/`Bone White` for neutral actions |
| **Title font (inline)** | SF Pro Text Semibold 17pt |
| **Title font (large)** | SF Pro Display Bold 34pt |
| **Leading items** | Back chevron (auto) or custom. Tinted `Signal Red`. |
| **Trailing items** | Max 2 visible items. Overflow goes to `ellipsis` menu. |
| **Bottom toolbar** | Background: same material as top. Items: Semibold 17pt, `Signal Red`. |

**SwiftUI skeleton:**
```swift
.toolbar {
    ToolbarItem(placement: .topBarLeading) {
        Button("Cancel") { dismiss() }
            .foregroundStyle(Color.Tempo.signal)
            .font(.system(size: 17, weight: .regular))
    }
    ToolbarItem(placement: .topBarTrailing) {
        Button("Save") { save() }
            .foregroundStyle(Color.Tempo.signal)
            .font(.system(size: 17, weight: .semibold))
    }
}
.toolbarBackground(.automatic, for: .navigationBar)
.toolbarTitleDisplayMode(.inline)
```

---

### 8.15 Context Menu Styling

| Property | Value |
|----------|-------|
| **Background** | System blur material (managed by iOS) |
| **Corner radius** | 14pt (system default) |
| **Text** | SF Pro Text Regular 17pt, `Ink Black` / `Bone White` |
| **Destructive text** | `Fail Red` (#DC2626) / dark: `#F87171` |
| **Icon** | 20pt, leading, matches text color |
| **Divider** | 0.5pt system separator |
| **Preview** | Scaled snapshot of source view, 12pt corner radius, Elevation 4 shadow |
| **Entry** | Source view scales to 0.96x, menu morphs in with blur. System spring. |
| **Haptic** | `UIImpactFeedbackGenerator(style: .medium)` on menu appear |

**SwiftUI skeleton:**
```swift
.contextMenu {
    Button {
        // edit action
    } label: {
        Label("Edit", systemImage: "pencil")
    }

    Button {
        // duplicate action
    } label: {
        Label("Duplicate", systemImage: "plus.square.on.square")
    }

    Divider()

    Button(role: .destructive) {
        // delete action
    } label: {
        Label("Delete", systemImage: "trash")
    }
} preview: {
    CardPreviewView(item: item)
        .frame(width: 300, height: 200)
}
```

---

### 8.16 Swipe Actions

#### Trailing Swipe Actions (Destructive)

| Property | Value |
|----------|-------|
| **Delete background** | `Fail Red` (#DC2626) / dark: `#F87171` |
| **Delete icon** | `trash.fill` 20pt, `#FFFFFF` |
| **Delete label** | "Delete", SF Pro Text Medium 13pt, `#FFFFFF` |
| **Archive background** | `Command Amber` (#F59E0B) / dark: `#FBBF24` |
| **Archive icon** | `archivebox.fill` 20pt, `#FFFFFF` |
| **Archive label** | "Archive", SF Pro Text Medium 13pt, `#FFFFFF` |
| **Full swipe** | Enabled for delete (full right-to-left swipe triggers delete with confirmation) |
| **Threshold** | 50% of row width triggers full swipe |
| **Haptic** | `.medium` impact when action button becomes visible. `.warning` on full swipe commit. |
| **Bounce** | Row bounces back with Spring Medium when action cancelled |

**SwiftUI skeleton:**
```swift
.swipeActions(edge: .trailing, allowsFullSwipe: true) {
    Button(role: .destructive) {
        deleteItem(item)
    } label: {
        Label("Delete", systemImage: "trash.fill")
    }
    .tint(Color.Tempo.error)

    Button {
        archiveItem(item)
    } label: {
        Label("Archive", systemImage: "archivebox.fill")
    }
    .tint(Color.Tempo.amber)
}
```

#### Leading Swipe Actions (Positive)

| Property | Value |
|----------|-------|
| **Complete background** | `Mission Green` (#22C55E) / dark: `#4ADE80` |
| **Complete icon** | `checkmark.circle.fill` 20pt, `#FFFFFF` |
| **Complete label** | "Done", SF Pro Text Medium 13pt, `#FFFFFF` |
| **Full swipe** | Enabled for complete/done action |
| **Haptic** | `.success` notification on complete |

```swift
.swipeActions(edge: .leading, allowsFullSwipe: true) {
    Button {
        completeItem(item)
    } label: {
        Label("Done", systemImage: "checkmark.circle.fill")
    }
    .tint(Color.Tempo.success)
}
```

---

### 8.17 Pull-to-Refresh Control

| Property | Value |
|----------|-------|
| **Tint color** | `Signal Red` (#E63946) / dark: `#FF4D5A` |
| **Style** | Custom circular progress that draws proportionally to pull distance |
| **Pull threshold** | 80pt to trigger refresh |
| **Ring stroke** | 3pt, round cap, `Signal Red` |
| **Ring diameter** | 24pt |
| **Spinning state** | Continuous rotation, 1 rotation per 1s, `Animation.linear(duration: 1).repeatForever(autoreverses: false)` |
| **Completion** | Ring shrinks to 0 scale over 200ms. Content refreshes with Tempo Cadence stagger. |
| **Haptic** | `.medium` impact when threshold reached on pull |

**SwiftUI skeleton:**
```swift
List {
    // content
}
.refreshable {
    await refreshData()
}
.tint(Color.Tempo.signal) // Colors the system refresh indicator
```

**Note:** For the custom ring-based pull-to-refresh (see Section 10.4), use a `ScrollView` with `GeometryReader` to track content offset and render the custom ring. The `.refreshable` modifier is acceptable for standard lists.

---

## 9. Motion Design Language

### 9.1 The Tempo Rhythm

Tempo's motion philosophy: **Military precision, not playful bounce.** Animations are crisp, purposeful, and interruptible. Nothing floats lazily. Everything snaps to attention.

### 9.2 Easing Curves as Cubic-Bezier

| Name | Cubic-Bezier | SwiftUI | Usage |
|------|-------------|---------|-------|
| **Snap** | `cubic-bezier(0, 0, 0.58, 1)` | `.easeOut` | Button press, toggle, instant response |
| **Smooth** | `cubic-bezier(0.42, 0, 0.58, 1)` | `.easeInOut` | Fade, color change, state transitions |
| **Enter** | `cubic-bezier(0, 0, 0.2, 1)` | Custom | Content appearing, slide in |
| **Exit** | `cubic-bezier(0.4, 0, 1, 1)` | Custom | Content disappearing, slide out |
| **Decelerate** | `cubic-bezier(0, 0, 0, 1)` | Custom | Data drawing (rings, charts) |

### 9.3 Spring Definitions

| Name | Response | Damping | SwiftUI | Usage |
|------|----------|---------|---------|-------|
| **Tight** | 0.25s | 0.85 | `.spring(response: 0.25, dampingFraction: 0.85)` | Segmented control slide, small element moves |
| **Medium** | 0.3s | 0.8 | `.spring(response: 0.3, dampingFraction: 0.8)` | Sheet appear, card expand, button release, tab content |
| **Loose** | 0.5s | 0.7 | `.spring(response: 0.5, dampingFraction: 0.7)` | Modal appear, FAB appear, page transitions |
| **Bouncy** | 0.4s | 0.5 | `.spring(response: 0.4, dampingFraction: 0.5)` | Celebration only — achievement unlock, level up, PR |
| **Drill** | 0.5s | 0.65 | `.spring(response: 0.5, dampingFraction: 0.65)` | Drill Sergeant alert entrance — forceful, authoritative |

### 9.4 Timing Tiers

| Tier | Duration | Curve | Usage |
|------|----------|-------|-------|
| **Micro** | 100ms | Snap (ease-out) | Button press, toggle, checkbox |
| **Small** | 200ms | Smooth (ease-in-out) | Fade in/out, color change, icon swap |
| **Medium** | 300ms | Spring Medium | Sheet appear, card expand, tab switch content |
| **Large** | 500ms | Spring Loose | Page transitions, modal appear, FAB appear |
| **Data** | 600-800ms | Spring Medium (response 0.6) | Chart draw, ring fill, progress bar |
| **Celebration** | 1000ms | Spring Bouncy | Achievement unlock, PR, level up |

### 9.5 Stagger Rhythm ("Tempo Cadence")

When multiple similar elements appear, they stagger entry using the Tempo Cadence:

| Element Type | Stagger Delay | Total Animation |
|-------------|---------------|-----------------|
| Dashboard quadrant cards | 60ms between each | 4 cards = 180ms total offset |
| Bar chart bars | 50ms between each | Varies by bar count |
| List rows (initial load) | 40ms between each, max 8 rows animated | 8 rows = 280ms total offset |
| Heatmap cells | 20ms per cell, row-by-row | Varies |
| Score ring layers | 150ms between each | 3 rings = 300ms total offset |
| Chart data points | 50ms per point | Varies |
| Streak dots | 30ms per dot (weekly view) | 7 dots = 180ms total offset |

**Rule**: Maximum 8 elements receive stagger animation. Beyond 8, elements appear instantly to prevent the animation from feeling slow.

### 9.6 Interruptible vs Committed Animations

| Category | Behavior | Examples |
|----------|----------|---------|
| **Interruptible** | Can be cancelled or reversed mid-flight. User gesture takes priority. New input immediately redirects the animation. | Sheet drag, scroll position, button press/release, tab switch, segmented control |
| **Committed** | Plays to completion once triggered. Cannot be interrupted. Used for celebratory or data-integrity moments. | Achievement unlock sequence, level up sequence, PR celebration, timer expire flash, ring draw on data load, score counter roll |

**SwiftUI implementation**: Interruptible animations use `.animation()` modifier. Committed animations use `withAnimation` blocks with completion handlers and ignore further state changes until complete.

### 9.7 Transition Types

| Transition | Animation | Duration | Type |
|------------|-----------|----------|------|
| **Push (navigation)** | System horizontal push | ~350ms (system) | Interruptible |
| **Modal (full screen)** | Slides up, scrim fades | 400ms Spring Loose | Interruptible |
| **Bottom sheet** | Slides up, spring physics, interactive gesture | 350ms Spring Medium | Interruptible |
| **Tab switch** | Cross-fade content | 200ms Smooth | Interruptible |
| **Drill Sergeant alert** | Slides up + red border pulse | 500ms Spring Drill | Committed (border pulse) |
| **Card expansion** | Scale + clip path reveal | 300ms Spring Medium | Interruptible |

---

## 10. Micro-Interaction Choreography

### 10.1 Tab Switching

**Trigger**: User taps a tab bar item.

| Step | Time | Animation | Detail |
|------|------|-----------|--------|
| 1 | 0ms | Previous tab icon: color → `Concrete`, weight Bold → Regular | 100ms Smooth |
| 2 | 0ms | New tab icon: scale 1.0 → 1.2 → 1.0 (bounce), color `Concrete` → `Signal Red`, weight Regular → Bold | 300ms Spring Medium |
| 3 | 0ms | Content cross-fade: old view fades out (opacity 1→0), new view fades in (opacity 0→1) | 200ms Smooth |
| 4 | 0ms | Haptic: `UISelectionFeedbackGenerator().selectionChanged()` | Immediate |

**Reduced motion**: No icon bounce, just color change. Content: instant swap, no cross-fade.

### 10.2 Card Expansion

**Trigger**: User taps a dashboard quadrant card or any expandable card.

| Step | Time | Animation | Detail |
|------|------|-----------|--------|
| 1 | 0ms | Card pressed: scale 0.96x | 100ms Snap |
| 2 | 100ms | Card released: scale back to 1.0 | 150ms Spring Tight |
| 3 | 150ms | Navigation push to detail screen | System push (~350ms) |
| 4 | 150ms | Haptic: `.light` impact | On release |

### 10.3 Score Counting

**Trigger**: Dashboard loads or score value changes.

| Step | Time | Animation | Detail |
|------|------|-----------|--------|
| 1 | 0ms | Score Display text begins counter roll from old value (or 0) to new value | Each digit changes independently |
| 2 | 0-800ms | Numbers increment/decrement with easing: fast at start, decelerates near target | 800ms Decelerate curve |
| 3 | 800ms | If score increased: brief scale pulse 1.0 → 1.03 → 1.0 on the number | 200ms Spring Tight |
| 4 | 800ms | Haptic: `.success` notification if score went up, `.error` if down, none if same | On settle |

**Implementation**: Use `Timer.publish(every: 0.016)` (60fps) to update displayed integer value along a deceleration curve.

**Reduced motion**: Instant value change, no counter roll.

### 10.4 Pull-to-Refresh

**Trigger**: User pulls down on scroll view.

| Step | Time | Animation | Detail |
|------|------|-----------|--------|
| 1 | Gesture | Custom progress ring draws proportional to pull distance (0pt pull = 0%, 80pt pull = 100%) | Continuous, tied to gesture |
| 2 | Threshold (80pt pull) | Ring completes circle, haptic fires | `UIImpactFeedbackGenerator(style: .medium)` |
| 3 | Release | Ring detaches from gesture, starts spinning continuously (1 rotation per 1s) | `Animation.linear(duration: 1).repeatForever(autoreverses: false)` |
| 4 | Data loaded | Ring stops spinning, shrinks to 0 scale, content refreshes with cross-fade | 200ms Smooth |
| 5 | Content settle | If staggered content, apply Tempo Cadence (40ms stagger per card/row) | Up to 8 elements |

### 10.5 Skeleton to Content Transition

**Trigger**: Data finishes loading, skeleton placeholders are replaced with real content.

| Step | Time | Animation | Detail |
|------|------|-----------|--------|
| 1 | 0ms | Shimmer gradient stops animating, holds at neutral position | Immediate |
| 2 | 0ms | Skeleton shapes fade out (opacity 1→0) | 150ms Snap |
| 3 | 50ms | Real content fades in (opacity 0→1) with slight upward movement (translateY 4pt → 0pt) | 200ms Spring Tight |
| 4 | If multiple cards | Apply Tempo Cadence stagger: 60ms between cards | Max 8 cards animated |

**Reduced motion**: Instant swap, no fade/translate.

### 10.6 Achievement Unlock

**Trigger**: User earns an achievement.

| Step | Time | Animation | Detail |
|------|------|-----------|--------|
| 1 | 0ms | Card background pulses once (opacity 1→0.9→1) | 200ms |
| 2 | 0ms | Badge icon scale 0.9 → 1.0 with Spring Bouncy | 400ms |
| 3 | 100ms | Badge icon rotates 360 degrees | 600ms ease-in-out |
| 4 | 200ms | Gold shimmer gradient sweeps left→right across card | 300ms linear |
| 5 | 300ms | XP badge appears (scale 0→1.1→1.0, float up 8pt) | 300ms Spring Bouncy |
| 6 | 0ms | Haptic: `.success` notification | Immediate |

**Reduced motion**: Simple fade-in of unlocked state. No rotation, no shimmer, no bounce.

### 10.7 Error to Retry Transition

**Trigger**: User taps "Retry" on an error state.

| Step | Time | Animation | Detail |
|------|------|-----------|--------|
| 1 | 0ms | Error icon + text fade out | 150ms Smooth |
| 2 | 100ms | Loading spinner fades in at center | 150ms Smooth |
| 3 | On success | Spinner fades out, content applies skeleton→content transition (10.5) | Standard timing |
| 4 | On second failure | Spinner fades out, error state fades back in with a slight shake (translateX: 0→-6→6→-4→4→0) | 400ms Spring Tight |
| 5 | On second failure | Haptic: `.error` notification | On shake start |

### 10.8 Empty to Populated Transition

**Trigger**: User adds first item to a previously empty list.

| Step | Time | Animation | Detail |
|------|------|-----------|--------|
| 1 | 0ms | Empty state icon + text + CTA scale down (0.95) and fade out | 200ms Smooth |
| 2 | 150ms | New item appears with Tempo Cadence entry: fade in + translateY (12pt → 0pt) | 300ms Spring Medium |
| 3 | 250ms | Haptic: `.success` notification | On new item settle |

### 10.9 Notification Banner Entrance/Exit

**Trigger**: Push notification received while app is in foreground.

| Step | Time | Animation | Detail |
|------|------|-----------|--------|
| **Entrance** | | | |
| 1 | 0ms | Banner slides down from -60pt (above safe area) to 8pt below safe area | 300ms Spring Medium |
| 2 | 0ms | Haptic: semantic type (`.success`, `.warning`, `.error`) | Immediate |
| **Hold** | 3000ms | Static | |
| **Exit** | | | |
| 3 | 3000ms | Banner slides up to -60pt + opacity 1→0 | 200ms Snap |

**Swipe to dismiss**: User swipes up on banner. Banner follows finger with pan gesture, if released with upward velocity >200pt/s, dismiss with 150ms exit. Otherwise, snap back.

---

## 11. Loading State Patterns

### 11.1 Shimmer Gradient Specification

All skeleton loaders share the same shimmer animation.

| Property | Light Mode | Dark Mode |
|----------|------------|-----------|
| **Gradient angle** | 20 degrees (slight diagonal) | 20 degrees |
| **Stop 1** | `#E5E7EB` at 0% | `#38383A` at 0% |
| **Stop 2** | `#F9FAFB` at 50% | `#48484A` at 50% |
| **Stop 3** | `#E5E7EB` at 100% | `#38383A` at 100% |
| **Translation** | -100% → +100% (full sweep left to right) | Same |
| **Duration** | 1.5s per sweep | Same |
| **Easing** | ease-in-out | Same |
| **Loop** | Infinite | Same |

**SwiftUI implementation:**
```swift
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1.0
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: shimmerHighlight, location: 0.5),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .init(x: phase - 0.5, y: 0.3),
                    endPoint: .init(x: phase + 0.5, y: 0.7)
                )
                .clipped()
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 2.0
                }
            }
    }

    private var shimmerHighlight: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.white.opacity(0.4)
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}
```

### 11.2 Skeleton Definitions Per Component

#### Standard Card Skeleton

| Placeholder | Shape | Width | Height | Corner Radius | Position |
|-------------|-------|-------|--------|---------------|----------|
| Title bar | Rounded rect | 60% of card width | 12pt | 6pt | Top-left, flush with card padding |
| Subtitle bar | Rounded rect | 40% of card width | 10pt | 6pt | 8pt below title bar |
| Content block | Rounded rect | 100% of card width | 80pt | 6pt | 12pt below subtitle bar |

#### Dashboard Quadrant Skeleton

| Placeholder | Shape | Width | Height | Corner Radius | Position |
|-------------|-------|-------|--------|---------------|----------|
| Icon circle | Circle | 20pt | 20pt | 10pt | Top-left, 12pt padding |
| Label bar | Rounded rect | 40% | 10pt | 5pt | 6pt right of icon circle, vertically centered |
| Metric block | Rounded rect | 50% | 24pt | 6pt | Centered vertically and horizontally |
| Sub-metric | Rounded rect | 30% | 8pt | 4pt | Bottom-left, 12pt padding |

#### Stat Card Skeleton

| Placeholder | Shape | Width | Height | Corner Radius | Position |
|-------------|-------|-------|--------|---------------|----------|
| Label bar | Rounded rect | 30% | 8pt | 4pt | Top-left |
| Value block | Rounded rect | 50% | 20pt | 6pt | 4pt below label |
| Trend indicator | Rounded rect | 24pt | 12pt | 4pt | Top-right |

#### List Row Skeleton

| Placeholder | Shape | Width | Height | Corner Radius | Position |
|-------------|-------|-------|--------|---------------|----------|
| Avatar (if applicable) | Circle | 40pt | 40pt | 20pt | Leading, vertically centered |
| Title bar | Rounded rect | 60% | 12pt | 6pt | 12pt right of avatar (or leading) |
| Subtitle bar | Rounded rect | 35% | 10pt | 5pt | 6pt below title |
| Trailing value | Rounded rect | 20% | 12pt | 4pt | Trailing, vertically centered |

#### Chart Skeleton

| Placeholder | Shape | Width | Height | Corner Radius | Position |
|-------------|-------|-------|--------|---------------|----------|
| Chart area | Rounded rect | 100% | 200pt (standard) / 120pt (compact) | 8pt | Full width |
| Horizontal line 1 | Rounded rect | 100% | 1pt | 0pt | 25% from top |
| Horizontal line 2 | Rounded rect | 100% | 1pt | 0pt | 50% from top |
| Horizontal line 3 | Rounded rect | 100% | 1pt | 0pt | 75% from top |

#### Workout Card Skeleton

| Placeholder | Shape | Width | Height | Corner Radius | Position |
|-------------|-------|-------|--------|---------------|----------|
| Left accent bar | Rounded rect | 4pt | 100% | 2pt | Left edge |
| Icon circle | Circle | 24pt | 24pt | 12pt | Top-left after accent |
| Title bar | Rounded rect | 50% | 14pt | 6pt | Right of icon |
| Duration bar | Rounded rect | 15% | 10pt | 4pt | Top-right |
| Subtitle bar | Rounded rect | 65% | 10pt | 5pt | Below title row |
| Tag row | 3x rounded rects | 20% each | 8pt | 4pt | Bottom, 8pt gap between |

### 11.3 Loading Text Patterns

While data loads, any visible text placeholder should use drill-sergeant voice:

| Context | Loading Text | Font |
|---------|-------------|------|
| Dashboard | "Assembling briefing..." | Caption 1, tertiary |
| Training | "Loading your orders..." | Caption 1, tertiary |
| Recovery | "Pulling vitals..." | Caption 1, tertiary |
| Study | "Checking your intel..." | Caption 1, tertiary |
| Profile | "Compiling your record..." | Caption 1, tertiary |
| General | "Stand by..." | Caption 1, tertiary |

---

## 12. Error State Design Patterns

### 12.1 Error Severity Levels

| Level | Pattern | When to Use |
|-------|---------|-------------|
| **Inline** | Red border + error text below field | Form validation failures |
| **Toast** | Top-of-screen temporary notification | Non-critical API errors, transient failures |
| **Banner** | Persistent strip below nav bar | Connectivity issues, degraded state |
| **Full-screen** | Centered error with retry | Screen-level data load failure |
| **Drill Sergeant Alert** | Modal overlay with red glow | Critical failures, account issues |

### 12.2 Inline Error

| Property | Value |
|----------|-------|
| **Trigger** | Field validation fails on blur or submit |
| **Input border** | Transitions to 2pt `Fail Red` (#DC2626) |
| **Error text** | Appears 4pt below field. Footnote (13pt Regular), `Fail Red`. |
| **Animation** | Error text fades in (opacity 0→1) + field border color transitions. 200ms Smooth. Field shakes once (translateX: 0→-4→4→0, 200ms). |
| **Haptic** | `.error` notification |
| **Clearing** | When user starts typing in errored field, border returns to focused state (2pt Ink Black). Error text fades out 150ms. |

**Copy patterns:**
- "Required. This field can't be empty."
- "Invalid format. Use numbers only."
- "Must be between {min} and {max}."
- "Too short. Minimum {n} characters."

### 12.3 Toast Error

| Property | Value |
|----------|-------|
| **Trigger** | Non-critical API failure (save failed, sync failed) |
| **Icon** | `xmark.circle.fill` 20pt, `Fail Red` |
| **Background** | `Ink Black` at 95% |
| **Text** | `Bone White`, Body |
| **Duration** | 3s auto-dismiss |

**Copy patterns:**
- "Save failed. Check your connection."
- "Sync error. Will retry automatically."
- "Action failed. Try again."

### 12.4 Banner Error (Persistent)

| Property | Value |
|----------|-------|
| **Trigger** | Ongoing connectivity issue, degraded service |
| **Background** | `#FEF2F2` (light) / `#450A0A` (dark) |
| **Left accent** | 4pt `Fail Red` |
| **Icon** | `wifi.slash` or `exclamationmark.triangle.fill` 20pt, `Fail Red` |
| **Text** | Body, primary text |
| **Dismiss** | Only when condition resolves. No manual dismiss for connectivity banners. |

**Copy patterns:**
- "You're offline. Showing cached data."
- "Connection unstable. Some features limited."
- "Whoop sync failed. Last update: 2 hours ago."
- "Server maintenance. Read-only mode."

### 12.5 Full-Screen Error

| Property | Value |
|----------|-------|
| **Trigger** | Screen-level data load failure (no cached data available) |
| **Layout** | Centered in available space, same as empty state |
| **Icon** | `exclamationmark.triangle.fill` 48pt, `Fail Red` |
| **Title** | Title 3, primary text |
| **Message** | Body, secondary text |
| **Primary CTA** | Secondary Button, "Retry" |
| **Secondary CTA** | Ghost Button, "Go Back" (when back navigation is possible) |

**Copy patterns:**

| Failure Type | Title | Message |
|-------------|-------|---------|
| Network timeout | "Connection timed out." | "Check your signal and try again." |
| Server error (5xx) | "Server issue." | "Not your fault. We're on it. Retry in a moment." |
| Data parsing error | "Something broke." | "Unexpected data. Retry or contact support." |
| Auth expired | "Session expired." | "Sign in again to continue." |
| Rate limited | "Slow down." | "Too many requests. Wait a moment and retry." |

**Retry behavior:**
- First retry: immediate on tap
- Second retry: show subtle "Still trying..." text change
- Third+ retry: change CTA to "Try Again Later" + show Ghost "Contact Support"
- Auto-retry: network errors auto-retry when connectivity restores (observe `NWPathMonitor`)

### 12.6 Drill Sergeant Error (Critical)

Reserved for critical situations only. Uses the Drill Sergeant Alert component.

| Trigger | Header | Message | Detail |
|---------|--------|---------|--------|
| Account suspended | "STAND DOWN" | "Account suspended." | "Contact support to resolve." |
| Data corruption | "CRITICAL FAILURE" | "Data integrity issue detected." | "Your data may need recovery." |
| Forced update | "UPDATE REQUIRED" | "You're running outdated firmware." | "Update to continue." |

---

## 13. Touch Feedback Specifications

### 13.1 Feedback Timing Model

Every tappable element follows this timing model:

```
[Touch Down] → [Highlight Delay] → [Visual Press State] → [Touch Up] → [Release Animation] → [Haptic]
```

### 13.2 Per-Element Specification

#### Primary Button

| Property | Value |
|----------|-------|
| **Highlight delay** | 0ms (instant) |
| **Press animation** | Scale 1.0 → 0.97, bg #E63946 → #C1303B | 100ms Snap |
| **Release animation** | Scale 0.97 → 1.0, bg #C1303B → #E63946 | 200ms Spring Medium |
| **Haptic type** | `UIImpactFeedbackGenerator(style: .medium)` |
| **Haptic timing** | On touch down (immediate) |
| **Haptic intensity** | 1.0 (default) |

#### Secondary Button

| Property | Value |
|----------|-------|
| **Highlight delay** | 0ms |
| **Press animation** | Scale 0.97, bg transparent → #0D0D0D at 5% | 100ms Snap |
| **Release animation** | Scale 1.0, bg clear | 200ms Spring Medium |
| **Haptic type** | `UIImpactFeedbackGenerator(style: .light)` |
| **Haptic timing** | On touch down |
| **Haptic intensity** | 1.0 |

#### Destructive Button

| Property | Value |
|----------|-------|
| **Highlight delay** | 0ms |
| **Press animation** | Scale 0.97, bg transparent → #DC2626 at 10% | 100ms Snap |
| **Release animation** | Scale 1.0, bg clear | 200ms Spring Medium |
| **Haptic type** | `UINotificationFeedbackGenerator().notificationOccurred(.warning)` |
| **Haptic timing** | On touch down |

#### Ghost Button

| Property | Value |
|----------|-------|
| **Highlight delay** | 0ms |
| **Press animation** | bg transparent → accent at 8% | 100ms Snap |
| **Release animation** | bg clear | 150ms Snap |
| **Haptic type** | `UIImpactFeedbackGenerator(style: .light)` |
| **Haptic timing** | On touch down |
| **Haptic intensity** | 0.7 |

#### Icon-Only Button

| Property | Value |
|----------|-------|
| **Highlight delay** | 0ms |
| **Press animation** | bg transparent → #0D0D0D at 8% | 80ms Snap |
| **Release animation** | bg clear | 150ms Snap |
| **Haptic type** | `UIImpactFeedbackGenerator(style: .light)` |
| **Haptic timing** | On touch down |
| **Haptic intensity** | 0.6 |

#### FAB

| Property | Value |
|----------|-------|
| **Highlight delay** | 0ms |
| **Press animation** | Scale 0.92, bg darken, shadow blur increase | 120ms Snap |
| **Release animation** | Scale 1.0, restore | 250ms Spring Loose |
| **Haptic type** | `UIImpactFeedbackGenerator(style: .medium)` |
| **Haptic timing** | On touch down |
| **Haptic intensity** | 1.0 |

#### List Row

| Property | Value |
|----------|-------|
| **Highlight delay** | 80ms (prevents accidental highlights during scroll) |
| **Press animation** | bg → `#F3F4F6` (light) / `#2C2C2E` (dark) | 100ms Smooth |
| **Release animation** | bg → original | 200ms Smooth |
| **Haptic type** | None (silent for list navigation) |

#### Card (Tappable)

| Property | Value |
|----------|-------|
| **Highlight delay** | 0ms |
| **Press animation** | Scale 0.97, bg dims 3% | 150ms Spring Tight |
| **Release animation** | Scale 1.0, bg restores | 200ms Spring Medium |
| **Haptic type** | `UIImpactFeedbackGenerator(style: .light)` |
| **Haptic timing** | On touch down |
| **Haptic intensity** | 0.8 |

#### Dashboard Quadrant Card

| Property | Value |
|----------|-------|
| **Highlight delay** | 0ms |
| **Press animation** | Scale 0.96 | 100ms Snap |
| **Release animation** | Scale 1.0 | 200ms Spring Medium |
| **Haptic type** | `UIImpactFeedbackGenerator(style: .light)` |
| **Haptic timing** | On touch down |
| **Haptic intensity** | 0.8 |

#### Tab Bar Item

| Property | Value |
|----------|-------|
| **Highlight delay** | 0ms |
| **Press animation** | Icon bounces scale 1.0 → 1.2 → 1.0 | 300ms Spring Medium |
| **Haptic type** | `UISelectionFeedbackGenerator().selectionChanged()` |
| **Haptic timing** | On selection change |

#### Segmented Control Segment

| Property | Value |
|----------|-------|
| **Highlight delay** | 0ms |
| **Press animation** | Indicator slides to new position | 250ms Spring Tight |
| **Haptic type** | `UISelectionFeedbackGenerator().selectionChanged()` |
| **Haptic timing** | On selection change |

#### Toggle

| Property | Value |
|----------|-------|
| **Highlight delay** | 0ms |
| **Press/release** | System standard (250ms spring) |
| **Haptic type** | `UIImpactFeedbackGenerator(style: .light)` |
| **Haptic timing** | On state change |
| **Haptic intensity** | 0.8 |

#### Slider

| Property | Value |
|----------|-------|
| **Highlight delay** | 0ms |
| **Press animation** | Thumb scale 1.0 → 1.15, shadow blur 4→8pt | 100ms Snap |
| **Release animation** | Thumb scale 1.15 → 1.0, shadow restore | 200ms Spring Tight |
| **Haptic type** | `UISelectionFeedbackGenerator().selectionChanged()` |
| **Haptic timing** | At each discrete step (if stepped) |

#### Number Stepper

| Property | Value |
|----------|-------|
| **Highlight delay** | 0ms |
| **Press animation** | Button bg dims slightly | 80ms Snap |
| **Release animation** | Button bg restores | 100ms Snap |
| **Haptic type** | `UIImpactFeedbackGenerator(style: .light)` |
| **Haptic timing** | On each step |
| **Haptic intensity** | 0.6 |
| **Long press acceleration** | 300ms delay → 100ms interval → 50ms interval after 2s |

### 13.3 Haptic Rules

- Never stack haptics within 50ms of each other (except intentional sequences: timer expire, drill sergeant)
- Always respect `UIAccessibility.isReduceMotionEnabled` — no change to haptics (haptics are independent of motion)
- Always respect system "Reduce Haptics" setting
- Prepare haptic generators before triggering (call `.prepare()` in advance for latency-sensitive contexts)
- Custom sequences (3x heavy for drill sergeant): use `DispatchQueue.main.asyncAfter` with 100ms intervals
- **iOS 17+ preferred API**: Use `.sensoryFeedback(_:trigger:)` modifier in SwiftUI instead of UIKit generators for simple cases. For custom sequences and `.prepare()` optimization, continue using UIKit generators.

---

## 14. Responsive Breakpoints

### 14.1 Device Targets

| Device | Screen Width | Screen Height | Scale | Horizontal Size Class |
|--------|-------------|---------------|-------|----------------------|
| **iPhone SE (3rd gen)** | 375pt | 667pt | 2x | Compact |
| **iPhone 15** | 393pt | 852pt | 3x | Compact |
| **iPhone 15 Pro Max** | 430pt | 932pt | 3x | Compact |
| **iPad (10th gen)** | 820pt | 1180pt | 2x | Regular (landscape) |

### 14.2 Layout Adaptations by Breakpoint

#### Screen Edge Margins

| Device | Margin |
|--------|--------|
| iPhone SE | 16pt (reduced from 20pt to recover space) |
| iPhone 15 | 20pt (standard) |
| iPhone 15 Pro Max | 20pt (standard) |
| iPad | 24pt (or `readableContentGuide`) |

#### Dashboard Quadrant Cards

| Device | Card Width | Card Height | Grid Gap |
|--------|-----------|-------------|----------|
| iPhone SE | (375 - 16 - 16 - 12) / 2 = **165.5pt** | 165.5pt | 12pt |
| iPhone 15 | (393 - 20 - 20 - 12) / 2 = **170.5pt** | 170.5pt | 12pt |
| iPhone 15 Pro Max | (430 - 20 - 20 - 12) / 2 = **189pt** | 189pt | 12pt |
| iPad | 3-column grid, card width ~250pt, aspect ratio 4:3 | 187.5pt | 16pt |

#### Score Ring Size

| Device | Dashboard Main Ring | Module Detail Ring |
|--------|--------------------|--------------------|
| iPhone SE | 160pt (reduced) | 100pt |
| iPhone 15 | 200pt (standard) | 120pt |
| iPhone 15 Pro Max | 200pt (standard) | 120pt |
| iPad | 240pt (enlarged) | 160pt |

#### Typography Scale Adjustments (iPhone SE)

On iPhone SE (375pt width), apply these reductions to prevent truncation:

| Style | Standard | iPhone SE |
|-------|----------|-----------|
| Score Display | 64pt | 52pt |
| Timer Display | 56pt | 44pt |
| Large Title | 34pt | 30pt |
| Data Large | 24pt | 20pt |

All other styles remain unchanged.

#### Chart Heights

| Device | Standard Chart | Compact Chart |
|--------|---------------|---------------|
| iPhone SE | 160pt (reduced) | 100pt |
| iPhone 15 | 200pt | 120pt |
| iPhone 15 Pro Max | 200pt | 120pt |
| iPad | 280pt (enlarged) | 160pt |

#### FAB Position

| Device | Trailing Offset | Bottom Offset (above tab bar) |
|--------|----------------|-------------------------------|
| iPhone SE | 16pt | 16pt |
| iPhone 15 | 20pt | 20pt |
| iPhone 15 Pro Max | 20pt | 20pt |
| iPad | 24pt | 24pt |

### 14.3 iPhone SE Specific Accommodations

The iPhone SE (375pt, no Dynamic Island, no home indicator) requires special attention:

1. **Dashboard**: Score ring reduced to 160pt. Greeting text uses Title 2 instead of Large Title. Quadrant cards use compact 12pt padding.
2. **Timer displays**: Font sizes reduced (see table above). Ring sizes reduced proportionally.
3. **Bottom sheets**: `.medium` detent becomes 55% (not 50%) to give more content space above the older home button area.
4. **Modal alerts**: Width becomes screen width - 32pt (not 48pt) to maximize usable area.
5. **Drill Sergeant Alert**: Width becomes screen width - 24pt.

### 14.4 iPad Adaptations (Future)

When iPad support is added:

1. **Split view**: Dashboard on left (fixed 380pt), detail on right (flexible)
2. **Navigation**: Sidebar navigation replaces tab bar in Regular horizontal size class
3. **Cards**: 3-column grid with 16pt gaps
4. **Charts**: Taller (280pt standard), wider tooltips, larger data points (8pt)
5. **Modals**: Presented as form sheets (540pt max width), not full-screen
6. **Score ring**: Enlarged to 240pt with proportionally thicker strokes

---

## 15. Layout Grid

### 15.1 Column System

Tempo uses a **fluid single-column** layout for most screens, with grids for specific contexts.

| Layout | Columns | Gutter | Usage |
|--------|---------|--------|-------|
| Single column | 1 | N/A | Lists, detail screens, forms |
| Two-column grid | 2 | 12pt | Dashboard quadrants, achievement grid, stat cards |
| Three-column grid | 3 | 8pt | Macro display (P/C/F), small metric cards |

### 15.2 Dashboard Layout Spec

```
|<-- margin -->|<-- card -->|<-- 12pt -->|<-- card -->|<-- margin -->|
                |<---- available width = screen - 2 * margin ---->|
                card width = (available - 12pt) / 2
                card height = card width (1:1 aspect ratio)
```

- **Top section**: Main score ring (200pt / 160pt SE) + greeting text. Full width.
- **Quadrant grid**: 2x2. Training (top-left), Recovery (top-right), Study (bottom-left), Nutrition (bottom-right).
- **Below grid**: Prescription card (full width), streak dots (full width), recent activity list.
- **Vertical gaps**: 16pt between main score and grid, 12pt between grid rows, 16pt between grid and prescription card.

### 15.3 Section Structure

Every screen follows this vertical rhythm:

```
[Navigation Bar]
  [8pt below safe area / nav bar]
  [Section Header — optional]
    [8pt gap]
    [Content cards/rows]
      [12pt between cards]
    [32pt gap to next section]
  [Section Header]
    [8pt gap]
    [Content]
  [48pt bottom padding above tab bar]
[Tab Bar]
```

### 15.4 Standard Dimensions

| Element | Height | Notes |
|---------|--------|-------|
| Standard list row | 56pt min | Expands with Dynamic Type |
| Exercise list row | 72pt min | Includes subtitle |
| Meal list row | 80pt min | Includes photo thumbnail |
| Section header | 40pt | 32pt above + 8pt below |
| Navigation bar (large) | 96pt | System standard |
| Navigation bar (inline) | 44pt | System standard |
| Tab bar | 49pt + safe area | System standard |
| Search bar | 40pt | Excluding margins |
| Segmented control | 36pt | |
| Bottom sheet grabber | 24pt | 8pt top + 5pt grabber + 11pt bottom |
| Button (primary/secondary) | 52pt | |
| Button (small) | 36pt | |
| Text field | 48pt | |
| FAB | 56pt | Circle |

---

## 16. Accessibility

### 16.1 Minimum Touch Targets

| Element | Minimum Size | Notes |
|---------|-------------|-------|
| All tappable elements | 44x44pt | Apple HIG minimum |
| Close/dismiss buttons | 44x44pt | Visual may be 24pt, hit area is 44pt |
| List row | Full width x 44pt min | |
| Tab bar item | Equal width x full height | |
| Slider thumb | 44x44pt hit area | Visual is 28pt |

### 16.2 VoiceOver Label Conventions

| Element | Label Format | Example |
|---------|-------------|---------|
| Score display | "{value} out of 100, {context} score" | "87 out of 100, daily score" |
| Progress ring | "{value} percent complete, {context}" | "65 percent complete, protein target" |
| Streak dots | "{count} day streak, {status}" | "23 day streak, active" |
| Recovery badge | "Recovery zone: {zone}, {value} percent" | "Recovery zone: green, 78 percent" |
| Chart | "Chart showing {metric} over {period}. Current: {value}. Trend: {trend}" | Descriptive |
| Timer | "{min} minutes {sec} seconds remaining, {type}" | "18 minutes 30 seconds remaining, focus" |
| XP badge | "Plus {value} experience points" | "Plus 50 experience points" |
| Achievement (locked) | "{name}, locked. Requirement: {req}" | "Iron Will, locked. Requirement: 30 consecutive workout days" |
| Achievement (unlocked) | "{name}, earned {date}. {desc}" | "Iron Will, earned March 15. 30 consecutive workout days" |
| Buttons | Action verb + context | "Start workout", "Log meal", "Dismiss alert" |
| Toggle | "{label}, {state}" | "Rest day mode, off" |

**Rules:**
- All images: descriptive `accessibilityLabel`
- Decorative images: `isAccessibilityElement = false`
- Custom components: correct `accessibilityTraits`
- Group related elements: `accessibilityElement(children: .combine)`
- Numbers spoken as words: use `accessibilityValue`

### 16.3 Color-Blind Safe Verification

| Color Pair | Deuteranopia | Protanopia | Tritanopia | Solution |
|------------|-------------|------------|------------|----------|
| Signal Red vs Mission Green | Distinguishable | Reduced | Fully distinguishable | Pair with icon shape (checkmark vs X) |
| Recovery Red vs Green | Reduced | Reduced | Distinguishable | Zone badges have text labels ("RED"/"GREEN") |
| Amber vs Green | Distinguishable | Distinguishable | Reduced | Star icon for XP, checkmark for success |
| Electric Blue vs Violet | Distinguishable | Distinguishable | Reduced | Different icon shapes per module |

**Rule**: Color must NEVER be the sole differentiator. Every color-coded element must also have a text label, distinct icon/shape, or pattern difference.

### 16.4 Reduced Motion Alternatives

When `UIAccessibility.isReduceMotionEnabled` is `true`:

| Standard Animation | Reduced Motion Alternative |
|-------------------|---------------------------|
| Spring animations | Dissolve/cross-fade, 200ms ease-in-out |
| Score counter roll | Instant value change |
| Ring draw animation | Instant fill |
| Chart draw animation | Instant render |
| Card scale on tap | Opacity 1.0 → 0.8 → 1.0 instead of scale |
| Timer ring | Static position, updates 1s intervals |
| Skeleton shimmer | Static gray placeholder |
| Achievement unlock | Simple fade-in, no particles, no rotation |
| Level up | Simple modal, no particles |
| Tab icon bounce | No bounce, color change only |
| Page transitions | Cross-dissolve instead of push/slide |
| Staggered entry | All items appear simultaneously |

---

## 17. Dark Mode

### 17.1 Philosophy

Dark mode uses surface lightness to convey elevation (higher = lighter), matching Apple's HIG. Shadows become invisible in dark mode — borders take over edge definition.

### 17.2 Surface Elevation Model

| Level | Surface | Light Hex | Dark Hex | Dark RGB |
|-------|---------|-----------|----------|----------|
| 0 — Base | Screen bg | `#F5F2ED` | `#0D0D0D` | 13, 13, 13 |
| 1 — Grouped | Section bg | `#EDEAE4` | `#1A1A1A` | 26, 26, 26 |
| 2 — Card | Cards, rows | `#FFFFFF` | `#1C1C1E` | 28, 28, 30 |
| 3 — Sheet | Bottom sheets | `#FFFFFF` | `#2C2C2E` | 44, 44, 46 |
| 4 — Popover | Menus, popovers | `#FFFFFF` | `#3A3A3C` | 58, 58, 60 |
| 5 — Overlay | Scrim | `#0D0D0D` @ 40% | `#000000` @ 50% | 0, 0, 0 |

**Rule**: In dark mode, use 0.5pt borders (`#38383A`) on cards and elevated surfaces. Exception: FAB retains shadow with `rgba(0, 0, 0, 0.40)`.

### 17.3 Image & Icon Treatment

| Element | Light Mode | Dark Mode |
|---------|------------|-----------|
| SF Symbols | Auto-adapt via Color assets | Same |
| Custom icons | Template rendering, tinted | Same |
| User photos | No treatment | No treatment |
| Placeholder images | `#E5E7EB` fill | `#38383A` fill |
| Decorative illustrations | Full color | Reduce brightness to 85% |
| Charts | Standard colors | Use dark variant colors (brighter) |
| Achievement badges | Standard metallic | Same (pop against dark) |
| Brand logo | Ink Black | Bone White |
| Skeleton loaders | `#E5E7EB`→`#F9FAFB` shimmer | `#38383A`→`#48484A` shimmer |

### 17.4 Dark Mode Gradient Stops

| Gradient | Light Stops | Dark Stops |
|----------|------------|------------|
| Score ring | `#E63946` → `#DC2626` | `#FF4D5A` → `#E63946` |
| XP bar | `#F59E0B` → `#EAB308` | `#FBBF24` → `#F59E0B` |
| Recovery high | `#22C55E` → `#16A34A` | `#4ADE80` → `#22C55E` |
| Recovery mid | `#EAB308` → `#CA8A04` | `#FACC15` → `#EAB308` |
| Recovery low | `#DC2626` → `#B91C1C` | `#F87171` → `#DC2626` |
| Hero dark | `#0D0D0D` → `#1F1F1F` | `#0D0D0D` → `#1A1A1A` |
| Study | `#3B82F6` → `#2563EB` | `#60A5FA` → `#3B82F6` |
| Shimmer | `#E5E7EB`→`#F9FAFB`→`#E5E7EB` | `#38383A`→`#48484A`→`#38383A` |

### 17.5 Implementation Checklist

- [ ] All colors defined as Color Assets in Xcode Asset Catalog with "Any" and "Dark" appearances
- [ ] No hardcoded hex values in SwiftUI views — always reference semantic tokens
- [ ] Test on OLED (iPhone 14 Pro+): `#0D0D0D` should appear as true black in dim lighting
- [ ] Verify all text contrast ratios against dark surfaces
- [ ] Confirm card borders at 0.5pt in dark mode (no shadows)
- [ ] Verify gradient stops use dark variants
- [ ] Recovery zone tint backgrounds use dark tints (not light tints at reduced opacity)
- [ ] Drill Sergeant Alert and Prescription Card use Ink Black in BOTH modes — verify correct
- [ ] Test with Smart Invert: Prescription Card excluded via `accessibilityIgnoresInvertColors = true`
- [ ] Test with Increase Contrast: borders and text should remain visible
- [ ] Test dark mode transitions: no flash of wrong colors during `traitCollectionDidChange`

---

## Appendix A: Swift Color Extension

```swift
import SwiftUI

extension Color {
    enum Tempo {
        // Primary
        static let ink = Color("tempo.color.primary.ink")
        static let bone = Color("tempo.color.primary.bone")
        static let signal = Color("tempo.color.primary.signal")

        // Secondary
        static let steel = Color("tempo.color.secondary.steel")
        static let concrete = Color("tempo.color.secondary.concrete")
        static let ash = Color("tempo.color.secondary.ash")

        // Accent
        static let amber = Color("tempo.color.accent.amber")
        static let electric = Color("tempo.color.accent.electric")
        static let violet = Color("tempo.color.accent.violet")

        // Semantic
        static let success = Color("tempo.color.semantic.success")
        static let warning = Color("tempo.color.semantic.warning")
        static let error = Color("tempo.color.semantic.error")
        static let info = Color("tempo.color.semantic.info")

        // Recovery
        static let recoveryGreen = Color("tempo.color.recovery.green")
        static let recoveryGreenBg = Color("tempo.color.recovery.green.bg")
        static let recoveryYellow = Color("tempo.color.recovery.yellow")
        static let recoveryYellowBg = Color("tempo.color.recovery.yellow.bg")
        static let recoveryRed = Color("tempo.color.recovery.red")
        static let recoveryRedBg = Color("tempo.color.recovery.red.bg")

        // Backgrounds
        static let bgPrimary = Color("tempo.color.bg.primary")
        static let bgSecondary = Color("tempo.color.bg.secondary")
        static let bgTertiary = Color("tempo.color.bg.tertiary")

        // Surfaces
        static let surfaceCard = Color("tempo.color.surface.card")
        static let surfaceSheet = Color("tempo.color.surface.sheet")
        static let surfaceElevated = Color("tempo.color.surface.elevated")
        static let surfaceOverlay = Color("tempo.color.surface.overlay")

        // Text
        static let textPrimary = Color("tempo.color.text.primary")
        static let textSecondary = Color("tempo.color.text.secondary")
        static let textTertiary = Color("tempo.color.text.tertiary")
        static let textDisabled = Color("tempo.color.text.disabled")
        static let textInverse = Color("tempo.color.text.inverse")

        // Borders
        static let borderDefault = Color("tempo.color.border.default")
        static let borderFocused = Color("tempo.color.border.focused")
        static let borderError = Color("tempo.color.border.error")
        static let dividerDefault = Color("tempo.color.divider.default")
        static let dividerHeavy = Color("tempo.color.divider.heavy")
    }
}
```

## Appendix B: Spacing Extension

```swift
import SwiftUI

enum TempoSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
    static let xxxxl: CGFloat = 40
    static let xxxxxl: CGFloat = 48

    // Component-specific
    static let cardPadding: CGFloat = 16
    static let cardPaddingCompact: CGFloat = 12
    static let screenEdge: CGFloat = 20
    static let screenEdgeSE: CGFloat = 16
    static let screenEdgeIPad: CGFloat = 24
    static let sectionGap: CGFloat = 32
    static let buttonPaddingH: CGFloat = 24
    static let buttonPaddingV: CGFloat = 14
}
```

## Appendix C: Shadow Extension

```swift
import SwiftUI

struct TempoShadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat

    static let elevation2Light = TempoShadow(
        color: Color.Tempo.ink.opacity(0.06), radius: 4, x: 0, y: 2
    )
    static let elevation3Light = TempoShadow(
        color: Color.Tempo.ink.opacity(0.15), radius: 10, x: 0, y: -4
    )
    static let elevation4Light = TempoShadow(
        color: Color.Tempo.ink.opacity(0.18), radius: 16, x: 0, y: 8
    )
    static let fabLight = TempoShadow(
        color: Color.Tempo.ink.opacity(0.20), radius: 6, x: 0, y: 4
    )
    static let fabDark = TempoShadow(
        color: Color.black.opacity(0.40), radius: 6, x: 0, y: 4
    )
    static let drillGlow = TempoShadow(
        color: Color.Tempo.signal.opacity(0.20), radius: 12, x: 0, y: 0
    )
    static let drillGlowSubtle = TempoShadow(
        color: Color.Tempo.signal.opacity(0.15), radius: 8, x: 0, y: 0
    )
    static let statCard = TempoShadow(
        color: Color.Tempo.ink.opacity(0.04), radius: 2, x: 0, y: 1
    )
}
```

## Appendix D: Motion Extension

```swift
import SwiftUI

enum TempoAnimation {
    // Easing curves
    static let snap = Animation.easeOut(duration: 0.1)
    static let smooth = Animation.easeInOut(duration: 0.2)

    // Springs
    static let springTight = Animation.spring(response: 0.25, dampingFraction: 0.85)
    static let springMedium = Animation.spring(response: 0.3, dampingFraction: 0.8)
    static let springLoose = Animation.spring(response: 0.5, dampingFraction: 0.7)
    static let springBouncy = Animation.spring(response: 0.4, dampingFraction: 0.5)
    static let springDrill = Animation.spring(response: 0.5, dampingFraction: 0.65)

    // Data
    static let dataSpring = Animation.spring(response: 0.6, dampingFraction: 0.8)
    static let dataDraw = Animation.easeOut(duration: 0.8)

    // Stagger helper
    static func stagger(index: Int, delay: Double = 0.06) -> Animation {
        springMedium.delay(Double(index) * delay)
    }
}
```

## Appendix E: Design Token Summary

| Category | Token Count |
|----------|-------------|
| Colors (light + dark) | 74 tokens |
| Typography styles | 22 styles (18 base + 4 specialized labels) |
| Spacing values | 10 scale steps + 27 component-specific |
| Corner radii | 10 values |
| Shadow definitions | 5 elevation levels + 3 special (drill glow, stat, FAB) |
| Opacity variants | 13 tokens |
| Gradients | 10 definitions (each with light + dark stops) |
| Motion curves | 5 easing + 5 spring + 7 stagger values |
| Haptic patterns | 14 distinct patterns |
| Icon definitions | 85+ icons with exact symbol, weight, size, color, context |
| Component specs | 41+ components with full state machines |
| Skeleton definitions | 6 component-specific skeleton layouts |
| Error patterns | 5 severity levels with copy templates |
| Responsive breakpoints | 4 device targets with per-component adaptations |

---

*This document was authored for the Tempo iOS application. Every value is a concrete implementation target — a hex code, a point value, a cubic-bezier curve, a haptic intensity. When in doubt, refer to the exact specification listed here. Do not approximate. Do not improvise. That is not the Tempo way.*

*Discipline in design. Discipline in code. Discipline in execution.*
