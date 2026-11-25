---
inclusion: fileMatch
fileMatchPattern: ["src/components/**", "src/features/**/*.tsx", "src/app/**/*.tsx", "**/*.css", "tailwind.config.*"]
---

# Pavio: design system

## Feel

Warm, personal, calm, a little nostalgic. A page, not a feed. Paper and ink, with blue for actions and identity and terracotta as a small human spark. Built for everyone.

## Colours (constant: never change shade between light and dark mode)

| Token | Hex | Use |
|---|---|---|
| `brand-blue` | `#2850F0` | logo arch, primary buttons, links, active states |
| `brand-terracotta` | `#C8553D` | the dot, small highlights only |
| `terracotta-text` | `#A83F2B` | terracotta used as small text on light backgrounds |
| `link-on-dark` | `#609AF8` | small blue text links in dark mode |

### Neutrals

| Token | Light | Dark |
|---|---|---|
| `canvas` (page) | `#FAF7F2` | `#151413` |
| `surface` (cards) | `#FFFFFF` | `#1F1D1B` |
| `surface-subtle` | `#F1ECE3` | `#2A2724` |
| `text` | `#1C1A17` | `#F4EFE6` |
| `text-secondary` | `#57524A` | `#B5AEA4` |
| `border` | `#DDD5C7` | `#38342F` |
| `border-input` | `#8A8175` | `#6E685F` |

### Semantic

| State | Text or icon | Light tint fill |
|---|---|---|
| success | `#1D633E` | `#E5F2EA` |
| warning | `#85550E` | `#FBF1DC` |
| error | `#9E2626` | `#FBE8E8` |
| info | `#1B4D9E` | `#E6EFFB` |

### Dot palette (user chosen colour of the dot in their mark)

Each colour has a light mode and a dark mode value; the app picks automatically. Default is Terracotta.

| Key | Light | Dark |
|---|---|---|
| terracotta | `#C8553D` | `#D17461` |
| cherry | `#B3263B` | `#E0566A` |
| mustard | `#93751A` | `#AD8A1F` |
| jade | `#348965` | `#3C9F76` |
| lagoon | `#208497` | `#259AB1` |
| violet | `#9662BC` | `#A77BC6` |

Never offer orange (political association in Kenya) or a blue close to the brand blue.

### Usage

About 65% neutrals, 20% text and structure, 5 to 8% blue, under 3% terracotta and dots. Directory and search screens stay calm; profile pages may be more expressive. Never fill large cards with brand blue or terracotta. Never place terracotta text on brand blue.

## Type

- **Dongle**: the wordmark only (use the logo files, never live text for the logo).
- **Bricolage Grotesque**: headings.
- **Inter**: body and interface.

## Logo files

In `public/brand/` (copied from `branding/`): `light`, `dark`, `white`, `black` versions of `primary`, `secondary`, `wordmark` and `icon`. Use `light` on light backgrounds, `dark` on dark backgrounds, `white` over photos or brand blue. `black` is for print only.

## Components and accessibility

- shadcn/ui as the base, restyled with the tokens above. Rounded corners (12px cards, full pill buttons echo the arch).
- Body text must meet WCAG AA (4.5:1). Interactive elements 3:1. Visible focus rings in brand blue.
- Glass effect only on the View as bar and overlays such as the story viewer.
- Touch targets at least 44px. Mobile first layouts.
- Every string comes from `t()`; never hard code copy.
- AI generated themes must pass a contrast check before they are applied.
