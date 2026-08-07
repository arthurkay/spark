# Website Redesign: Cal.com Light Theme

## Objective
Redesign the Spark landing page (docs/) to match cal.com's clean, modern SaaS aesthetic with a light/white theme, replacing the current dark Vercel-inspired design.

## Design Reference: cal.com
- **Background**: White (`#ffffff`) with subtle gray sections (`#f9fafb`)
- **Text**: Dark gray (`#111827`) for headings, medium gray (`#6b7280`) for body
- **Accent**: Cyan/blue (`#38bdf8`) for CTAs and highlights
- **Typography**: Large bold headings (Inter font), clean body text
- **Layout**: Generous whitespace, numbered steps, feature grids
- **Effects**: Subtle gradients, glass morphism cards, smooth animations

## Files to Modify
- `docs/index.html` — Complete rewrite
- `docs/styles.css` — Complete rewrite

## Structure (cal.com pattern)

### 1. Navigation
- Fixed top nav with logo, links (Showcase, Features, Get started), GitHub button
- White background with subtle border on scroll
- Clean, minimal

### 2. Hero Section
- Large bold heading: "Your AI coding companion, anywhere."
- Gradient text on key phrase (cyan → blue)
- Subtitle describing the product
- Two CTAs: "Get started" (primary) + "Star on GitHub" (secondary)
- Hero badge: "Mobile client for opencode"

### 3. Social Proof Bar
- "Trusted by developers" with logo placeholders or GitHub stars
- Subtle, not overwhelming

### 4. How It Works (Numbered Steps)
- 01, 02, 03 pattern like cal.com
- Step 1: Start the server (code block)
- Step 2: Connect from Spark (code block)
- Step 3: Start coding (description)
- Clean cards with step numbers

### 5. Showcase Section
- Phone mockups in a grid layout
- Featured card (chat) + side cards (home, terminal)
- Hover effects with subtle lift
- White card backgrounds with shadows

### 6. Features Grid
- 6 features in a 3x2 grid
- Icon + title + description
- Subtle hover effects
- Clean, minimal cards

### 7. Testimonials
- Carousel or grid of testimonials
- Company logos + quotes
- Social proof

### 8. FAQ Section
- Accordion-style questions
- Common questions about Spark, opencode, setup

### 9. CTA Section
- Final call-to-action
- "Ready to code from wherever you are?"
- Get started button

### 10. Footer
- Logo, links (GitHub, opencode, Server setup)
- Clean, minimal

## Color Palette
```css
--bg: #ffffff;
--bg-secondary: #f9fafb;
--text: #111827;
--text-secondary: #6b7280;
--text-tertiary: #9ca3af;
--border: #e5e7eb;
--border-hover: #d1d5db;
--cyan: #38bdf8;
--cyan-light: #e0f2fe;
--gradient: linear-gradient(135deg, #38bdf8 0%, #818cf8 100%);
```

## Typography
- Font: Inter (already loaded)
- Hero: 64px bold, -0.04em tracking
- Section headings: 40px bold, -0.03em tracking
- Body: 16px, 1.6 line-height
- Small: 14px for labels, badges

## Animations
- Scroll reveal with IntersectionObserver (existing pattern)
- Subtle hover lifts on cards
- Smooth transitions (0.3s ease)
- No heavy animations — clean and professional

## Responsive
- Mobile: single column, stacked layout
- Tablet: 2-column grids
- Desktop: full 3-column grids

## Implementation Steps

### Step 1: Rewrite styles.css
- Switch to light theme variables
- Update all color references
- Add new component styles (steps, testimonials, FAQ)
- Keep animation patterns

### Step 2: Rewrite index.html
- New structure following cal.com pattern
- Remove glow effects (dark theme only)
- Add numbered steps section
- Add testimonials section
- Add FAQ section
- Add app store badges

### Step 3: Verify
- Check responsive behavior
- Test animations
- Ensure all links work
- Verify screenshot paths

## Success Criteria
- [ ] Light/white theme matches cal.com aesthetic
- [ ] All sections render correctly
- [ ] Responsive on mobile/tablet/desktop
- [ ] Animations smooth and professional
- [ ] No broken links or images
