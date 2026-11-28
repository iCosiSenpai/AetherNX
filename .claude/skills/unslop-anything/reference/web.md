# The web

For web apps and websites: React, Next.js, Vue, Nuxt, Svelte, Astro, Angular, plain HTML and CSS, Tailwind, and component kits such as shadcn/ui.

Everything in [tells.md](tells.md) still applies, except section 3 (Website in a phone), which is for native apps. This file adds what is different on the web.

## Two kinds of page

Decide which one you are looking at, because they fail differently.

- **An app** is where people work: dashboards, editors, settings, admin, inboxes, checkout. Judge it like a mobile app: task path first, density that fits daily use, quiet chrome, the content carries the color. A landing-page hero inside an app is a tell.
- **A site** persuades someone to act: a landing page, pricing, a portfolio, a restaurant, an event. Judge it on whether a visitor understands the offer and finds the action within seconds, and whether it could belong to anyone else.

A product's marketing site and its app are two scopes. Review one at a time.

## The web floor

These break the web for real people. They are Critical or Noticeable, whatever the look.

- **Real controls.** Actions are `<button>`, navigation is `<a href>`. A `div`, `span`, `article` or other non-interactive element with a click handler is unreachable by keyboard and silent to screen readers [`clickable-div`].
- **Visible focus.** Every interactive element shows a `:focus-visible` style, in the palette, instantly. `outline: none` with nothing in its place locks keyboard users out [`focus-removed`].
- **Zoom stays on.** No `maximum-scale=1` or `user-scalable=no` [`zoom-disabled`]. Inputs at 16px stop iOS from zooming on focus.
- **Text alternatives.** Every content image has alt text, including framework image components such as `<Image>`, `<NuxtImg>`, Vuetify's `<v-img>` / `<VImg>` and Ionic's `<ion-img>` / `<IonImg>`; decoration has `alt=""` [`img-no-alt`].
- **URLs mean something.** The back button returns to the previous view. Filters, tabs, search, and pagination that someone would share live in the URL. Opening in a new tab works.
- **Contrast** 4.5:1 for body text and 3:1 for large text and meaningful icons, in light and dark.
- **Reduced motion.** Every animation has a `prefers-reduced-motion: reduce` fallback. Content is visible without it [`reduced-motion`].
- **No horizontal scroll** at 375 wide, and the layout holds at 1920: the content width is capped and centered, the gutters grow.
- **Forms** have labels (not placeholders as labels), the right `type` and `autocomplete`, errors next to the field in words, and the entered data kept after an error [`placeholder-label`].
- **Nothing invented.** No customer counts, logo walls, testimonials, ratings, or case studies the user did not supply [`unverified-claim`, `invented-stat`].

## Web tells

### App screens

- A dashboard that opens with a greeting and three stat cards instead of the thing the user came to do
- Every section in a bordered card, cards in a uniform grid, one radius everywhere
- Stat cards with sparklines, icons, and colored deltas with no "vs" (what changed, compared to what?)
- Charts with a rainbow of colors inside one series, glowing bars, or placeholder data
- A sidebar with an icon in a tinted square beside every item [`icon-tile`], or uneven row heights and gaps
- Tables that are cards on desktop, or cards that should have been a table
- `transition-all` [`transition-all`], cards that grow on hover [`hover-scale`], skeletons and dots that pulse forever [`decorative-pulse`]
- Modals for things that should be a page or an inline edit; toasts for errors the user has to act on

### Sites

- The centered hero: tracked-caps eyebrow pill [`tracked-caps-label`] ("✨ New: AI-powered"), a gradient headline [`gradient-text`, `slop-gradient`], a subhead that repeats it, two buttons, and a blurred blob behind
- A hero that does not show the product, or shows a hand-drawn fake browser window
- Three feature cards with an icon tile, a two-word title, and a sentence each, repeated for every section
- Logo walls, testimonial grids with stock avatars, "Trusted by 10,000+ teams", "10x faster" [`unverified-claim`]
- A pricing table with a glowing "Most popular" card and a checklist that is the same on every plan
- An email sign-up band at the end of every page, whatever the page is for
- Scroll-jacking, parallax, and every section fading up on scroll
- More than about 80 words on one screen of a landing page; a headline longer than two lines at 1280 wide
- The hero's headline, sentence, and main action not all visible at 1280 by 800

### The web's new default

The calm generated look on the web is specific enough to name: Inter or Geist everywhere, zinc or slate neutrals, `rounded-lg border shadow-sm` cards, `text-muted-foreground` under every title, a `Badge` on every row, a two-column bento grid, and a dark mode that is the same layout in gray. Kits like shadcn/ui are fine as building blocks; untouched defaults on every surface are the tell. Ask what in the page is specific to this product. If the answer is only the copy, it is the default.

## Native building blocks for the web

Prefer the platform to a custom imitation.

| Need | Use |
|---|---|
| Actions and links | `<button>`, `<a href>` |
| Dialogs | `<dialog>` with `showModal()`, or the project's accessible dialog component |
| Menus and popovers | the `popover` attribute, or the project's menu component with arrow-key support |
| Disclosure | `<details>` and `<summary>` |
| Choices | `<select>`, radio groups, checkboxes; `<input type="date">` and friends before a custom picker |
| Page changes | real routes and links; View Transitions for continuity |
| Layout | CSS grid with `minmax(0, 1fr)`, `clamp()` for type, container queries for components |
| Theming | CSS custom properties at `:root`, `prefers-color-scheme`, `color-scheme` |
| Motion | `transform` and `opacity`, named transition properties, `prefers-reduced-motion` |
| Browser surfaces | theme `::selection`, `accent-color`, `caret-color`, scrollbar colors, and focus rings from the palette |

## Checking it

- Screenshot the scoped pages with Playwright or the browser at 375, 768, 1280, and 1920 wide. Emulate dark with `colorScheme: 'dark'` and reduced motion with `reducedMotion: 'reduce'`.
- Zoom to 200% and check nothing overlaps or disappears.
- Tab through every changed page from the address bar. Every stop is visible and in reading order; Enter and Space work; Escape closes what opened.
- Run Lighthouse or the browser's accessibility panel for contrast and missing names. They catch a floor, not quality.
- For a live site with no code, save the page and work on a local copy; say in the report that the result is a redesign in code for whoever owns the site.
