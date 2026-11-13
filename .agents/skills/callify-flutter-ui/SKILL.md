---
name: callify-flutter-ui
description: UI design guidelines and patterns for the Callify Flutter app. Activates when working on UI improvements, redesigns, or new screens. Provides the app's design system, color palette, typography, and component patterns.
---

# Callify Flutter UI Design System

## Design Philosophy
Callify uses a **premium dark theme** with a modern, glassmorphic aesthetic. Every screen should feel alive with subtle animations, gradients, and micro-interactions.

## Color Palette

### Core Colors
- **Background**: `Color(0xFF0D171A)` — Deep dark blue-black
- **Surface**: `Color(0xFF172629)` — Slightly lighter dark teal
- **Mint Accent**: `Color(0xFF63DCC8)` — Primary accent color for CTAs, icons, badges
- **Input Background**: `Color(0xFF142225)` — Dark input fields
- **Muted Text**: `Color(0xFF9BAEB0)` — Secondary text, descriptions
- **White**: `Colors.white` — Primary text, headings

### Gradient Palettes
- **Card Gradient**: `LinearGradient(colors: [Color(0xFF1D4645), Color(0xFF173334), Color(0xFF192A30)])`
- **Call Screen**: `LinearGradient(colors: [Color(0xFF0A1628), Color(0xFF0F2440)])`
- **Ludo Theme**: `LinearGradient(colors: [Color(0xFF1A0A2E), Color(0xFF2D1B69)])` with gold `Color(0xFFFFD700)`

### Status Colors
- **Success/Online**: `Color(0xFF10B981)` — Emerald green
- **Error/Decline**: `Color(0xFFEF4444)` — Red
- **Warning**: `Color(0xFFF59E0B)` — Amber

## Typography
- **Font Family**: Google Fonts `Outfit` (set globally in MaterialApp)
- **Headings**: Bold (w700-w800), white, letter-spacing -0.35
- **Body**: Regular (w400-w500), white or muted
- **Labels**: Semi-bold (w600-w700), smaller sizes (11-13px)
- **Section Headers**: 18px, w700, white

## Component Patterns

### Cards
```dart
Container(
  padding: const EdgeInsets.all(20),
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(22),
    gradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF1D4645), Color(0xFF173334), Color(0xFF192A30)],
    ),
    border: Border.all(color: Colors.white.withValues(alpha: .07)),
  ),
)
```

### Buttons
- **Primary (Filled)**: Mint background `Color(0xFF63DCC8)`, dark text `Color(0xFF0D2725)`
- **Secondary (Outlined)**: White/muted foreground, subtle white border
- **Icon Buttons**: 46x46 containers with mint-alpha background, rounded corners 15

### Avatars
- Circular container with initial letter
- Deterministic color from name hash: `[Color(0xFF4ADBC4), Color(0xFFFFA477), Color(0xFF91AFFF), Color(0xFFF2C14E)]`
- Alpha background with matching border

### Badges/Pills
- Small rounded containers with dark background `Colors.black.withValues(alpha: .18)`
- Mint icon + white text, 12px font, w700

### Input Fields
- Filled with `Color(0xFF142225)`
- Border radius 14
- Focused border: mint 1px
- Enabled border: subtle white alpha
- White text, muted hint

### AppBar
- Background matches page background
- Transparent surface tint
- White back arrow
- Title: 19px, w700, white
- Actions: mint-colored icon buttons

### Scaffolds
- Always `backgroundColor: Color(0xFF0D171A)`
- SafeArea with `top: false`
- Max width constraint 620 for tablet support

## Animation Patterns
- **Pulse**: AnimationController 1500ms, scale 1.0-1.15, for loading/searching states
- **Fade transitions**: 300ms with Curves.easeInOut
- **Haptic feedback**: lightImpact for taps, heavyImpact for important actions
- **Shimmer loading**: Use gradient animation for skeleton loading states

## Screen Layout Pattern
```
Scaffold (dark bg)
  └── SafeArea
      └── ConstrainedBox (maxWidth: 620)
          └── ListView / Column
              ├── Hero Card (gradient, icon, stats)
              ├── Section Header (title + count badge)
              ├── Content Cards
              └── Bottom padding (36)
```

## Do's and Don'ts
✅ Use gradients, not flat solid backgrounds
✅ Add subtle borders with white alpha (.045 - .09)
✅ Use rounded corners (14-22px)
✅ Add haptic feedback on interactions
✅ Use mint accent consistently
✅ Add empty states with icon + title + description
❌ Don't use Material default colors
❌ Don't use flat/boring layouts
❌ Don't forget dark mode considerations
❌ Don't use text without proper contrast
❌ Don't skip loading/error states
