---
name: Lumina Vision
colors:
  surface: '#f9f9ff'
  surface-dim: '#cadaff'
  surface-bright: '#f9f9ff'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f1f3ff'
  surface-container: '#e8edff'
  surface-container-high: '#e0e8ff'
  surface-container-highest: '#d7e2ff'
  on-surface: '#041b3c'
  on-surface-variant: '#434654'
  inverse-surface: '#1d3052'
  inverse-on-surface: '#edf0ff'
  outline: '#737685'
  outline-variant: '#c3c6d6'
  surface-tint: '#0c56d0'
  primary: '#003d9b'
  on-primary: '#ffffff'
  primary-container: '#0052cc'
  on-primary-container: '#c4d2ff'
  inverse-primary: '#b2c5ff'
  secondary: '#825500'
  on-secondary: '#ffffff'
  secondary-container: '#feaa00'
  on-secondary-container: '#684300'
  tertiary: '#004e32'
  on-tertiary: '#ffffff'
  tertiary-container: '#006844'
  on-tertiary-container: '#72e9af'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#dae2ff'
  primary-fixed-dim: '#b2c5ff'
  on-primary-fixed: '#001848'
  on-primary-fixed-variant: '#0040a2'
  secondary-fixed: '#ffddb3'
  secondary-fixed-dim: '#ffb950'
  on-secondary-fixed: '#291800'
  on-secondary-fixed-variant: '#624000'
  tertiary-fixed: '#82f9be'
  tertiary-fixed-dim: '#65dca4'
  on-tertiary-fixed: '#002113'
  on-tertiary-fixed-variant: '#005235'
  background: '#f9f9ff'
  on-background: '#041b3c'
  surface-variant: '#d7e2ff'
typography:
  display-lg:
    fontFamily: Inter
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.02em
  headline-md:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
  headline-sm:
    fontFamily: Inter
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 28px
  body-lg:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '400'
    lineHeight: 28px
  body-md:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  label-caps:
    fontFamily: Atkinson Hyperlegible Next
    fontSize: 14px
    fontWeight: '700'
    lineHeight: 20px
    letterSpacing: 0.05em
  caption:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  base: 8px
  touch-target-min: 48px
  margin-mobile: 20px
  gutter: 16px
  stack-sm: 12px
  stack-md: 24px
---

## Brand & Style

The design system is centered on **inclusive empowerment** and **utilitarian warmth**. It serves users who rely on visual communication, requiring a UI that is highly legible, stable, and cognitively light.

The style is **Modern Minimalist with a focus on Clarity**. It prioritizes high-contrast touch targets and significant negative space to reduce visual noise, ensuring that the sign language video feed and smart home controls remain the focal points. The aesthetic avoids unnecessary decoration, opting for a functional, "instructional" elegance that feels both professional and approachable.

**Design Principles:**
- **Visual-First:** Information is conveyed through iconography and video before text.
- **Reduced Friction:** Large, predictable interactive zones to accommodate various motor abilities.
- **Calm Interaction:** A "soft-ui" backdrop minimizes glare and eye fatigue during long translation sessions.

## Colors

The palette is engineered for **AAA accessibility compliance**. 

- **Primary (#0052CC):** A deep, trustworthy blue used for main actions and branding. It provides high contrast against light backgrounds.
- **Secondary (#FFAB00):** A vivid amber used for "Warning" states or to highlight active smart home devices (e.g., a light being turned on).
- **Tertiary (#36B37E):** A clean green for "Success" states and "Connected" indicators.
- **Backgrounds:** Use a soft "off-white" (`#F4F5F7`) for the main canvas to reduce the harshness of pure white pixels, which can cause eye strain for users focusing intensely on sign language video.
- **Surface:** Pure white (`#FFFFFF`) is reserved for cards and interactive components to create a clear layer of separation from the canvas.

## Typography

This design system utilizes **Inter** for its systematic clarity and excellent legibility at various weights. For labels and critical UI metadata, it integrates **Atkinson Hyperlegible Next** to ensure maximum character differentiation, which is vital for users with varying visual acuity.

**Usage Rules:**
- **Text Alignment:** Left-align all primary text. Avoid justified text to maintain consistent word spacing.
- **High Contrast:** Ensure all text-to-background ratios exceed 4.5:1. 
- **Dynamic Type:** All sizes must scale proportionally with system-level font size adjustments.

## Layout & Spacing

The layout follows a **Fluid Grid** model with an emphasis on oversized touch targets. 

- **The 8px Rhythm:** All spacing, margins, and heights are multiples of 8px to ensure a consistent vertical cadence.
- **Mobile First:** A single-column layout is preferred for translation feeds. For smart home controls, a 2-column grid is used to keep buttons large and reachable.
- **The "Safe Zone":** The bottom 15% of the screen is reserved for the "Global Action Bar" (Camera Toggle, Home Control, Settings), ensuring these are always reachable with one thumb.
- **Video Aspect Ratio:** Sign language translation feeds should maintain a 4:3 or 16:9 ratio with clear "safety margins" to prevent UI overlays from obscuring the signer's hands or face.

## Elevation & Depth

This design system uses **Tonal Layers** rather than heavy shadows to convey depth. This approach maintains a clean, modern look while preventing visual "mud" that can distract from visual communication.

- **Level 0 (Canvas):** Soft-grey background (`#F4F5F7`).
- **Level 1 (Cards):** Pure white surface with a subtle 1px border (`#EBECF0`).
- **Level 2 (Active/Floating):** Use a low-opacity, ultra-diffused shadow (Blur: 12px, Y: 4px, Color: `#00000010`) to indicate interactive elements like floating translation bubbles or "Active" smart device toggles.
- **Focus States:** High-visibility 3px primary blue outlines are mandatory for all focused interactive elements to support keyboard and switch-access navigation.

## Shapes

The shape language is **Rounded (0.5rem / 8px)**. This radius offers a friendly, modern feel that balances the "technical" nature of smart home control with the "human" nature of sign language.

- **Interactive Elements:** Buttons and Input fields use a standard `8px` radius.
- **Status Indicators:** Small indicators (like "online" dots) should be fully circular.
- **Video Containers:** Mirror the card roundedness (`16px` for `rounded-lg`) to soften the edges of the camera feed.

## Components

### Buttons
- **Primary:** Solid Primary Blue with white text. Height: `56px` minimum for accessibility.
- **Secondary:** Outlined with a 2px stroke in Primary Blue.
- **Destructive:** Solid Red (`#DE350B`) with white text, used only for critical actions (e.g., Delete Device).

### Smart Home Cards
- **Structure:** Large icon (top left), Device Name (bold), Status Label (caption), and a large toggle switch or slider.
- **Interactive Area:** The entire card should be a touch target for toggling.

### Sign Language Feed
- **Overlays:** Text captions should appear on a semi-transparent dark background (80% opacity) at the bottom of the video feed to ensure legibility regardless of the video's background.
- **Gesture Area:** A dedicated "Camera View" component that maximizes the viewport while keeping the controls accessible.

### Input Fields
- **Styling:** Soft-grey background with a clear bottom border. 
- **Labels:** Labels must always be visible (never use placeholder-only inputs).
- **Feedback:** Success and Error messages must include an icon (Checkmark or Warning) to ensure the message is conveyed through more than just color.

### Accessibility-Specific: Hand Gesture Icons
- A custom icon set that represents common sign language categories (Numbers, Alphabet, Common Phrases) to help users navigate the library visually.