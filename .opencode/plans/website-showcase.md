# Website Screenshot Showcase Redesign Plan

## Current State
- 3-column grid with basic screenshots and one-line captions
- Screenshots have `border-radius: 12px` and a gradient caption overlay
- Clean but flat — no visual hierarchy, no animations, no depth

## Goal
Make the showcase feel like a professional product landing page — phone-like
frames, visual depth, subtle animations, and clear hierarchy.

---

## Changes

### 1. Phone-like screenshot frames (`styles.css`)

Wrap screenshots in a device frame effect using CSS:
- Taller border-radius on top corners (like a phone notch area)
- Subtle inner shadow for depth
- A thin bezel effect around the image
- Slight drop shadow for floating effect

```css
.screenshot {
  border-radius: 16px;
  box-shadow:
    0 0 0 1px var(--border),
    0 8px 32px rgba(0, 0, 0, 0.4);
  overflow: hidden;
}

.screenshot img {
  border-radius: 16px 16px 0 0;
}
```

### 2. Featured layout — make Chat the hero

Make the chat screenshot wider (spans 2 columns) with a description beside it,
and the other two stacked or side-by-side in the remaining space.

Layout:
```
[  Chat (large, 2 cols)  ] [ Home      ]
[                         ] [ Terminal  ]
```

This gives visual hierarchy — the chat experience is the primary selling point.

### 3. Hover effects

- Subtle scale-up on hover (`transform: scale(1.02)`)
- Glow effect using `box-shadow` with cyan accent (`#38bdf8`)
- Smooth transition

```css
.screenshot {
  transition: transform 0.2s ease, box-shadow 0.2s ease;
}
.screenshot:hover {
  transform: translateY(-4px);
  box-shadow:
    0 0 0 1px var(--border),
    0 12px 40px rgba(0, 0, 0, 0.5),
    0 0 20px rgba(56, 189, 248, 0.1);
}
```

### 4. Better captions

Replace the gradient overlay with a cleaner caption below the image:
- Feature name in bold
- One-line description
- Consistent height so cards align

### 5. Section header

Add a small label above the screenshots:
```
SHOWCASE
See what Spark can do
```

### 6. Responsive adjustments

- On mobile: stack screenshots vertically, chat first
- Keep the phone-frame effect on all sizes

---

## Files to Modify

| File | Change |
|------|--------|
| `docs/styles.css` | Phone frames, hover effects, featured layout, captions |
| `docs/index.html` | Restructure screenshots section for featured layout + descriptions |

## Estimated Lines
- CSS: ~60 lines modified/added
- HTML: ~20 lines restructured
