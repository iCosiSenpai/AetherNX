# Treatment

Read this before the first edit. The diagnosis says what is wrong. This says how to fix it without making a different mess.

The triage, the direction, and the pass order are adapted from [Unslop](https://github.com/heydamir/unslop) by Damir Sokolovsky ([@heydamir](https://x.com/heydamir)), licensed CC BY 4.0. The neighbor test, the waivers, and the fresh-context reviewer are adapted from [Hallmark](https://github.com/Nutlope/hallmark) (MIT).

## How much to change

Read the diagnosis honestly and call the case before you plan anything.

- **Heavy.** Generated tells across color, type, icons, copy, and layout, or a Task path or Truth score of 2 or less. Run the full treatment: direction, then every pass.
- **Light.** A screen that is mostly designed, with a few tells left. Fix only the findings. Keep the palette, type, layout, and visuals. Bigger ideas go in the report as suggestions, not changes.
- **Healthy.** Say so plainly. Offer two or three small refinements with exact values, and apply them only if the user agrees. Never change a good screen just to make it different.

## Direction

For a heavy case, write five short lines before touching anything, derived from what the product does and who uses it, never from what is in fashion. Show them with the diagnosis and wait for the user's answer, because changing direction later means redoing everything. Skip the wait only when the user already said to go ahead.

- **Product.** What it does and for whom, in one plain sentence.
- **Use.** Where and how people use it: one-handed on a train, at a desk all day, in a kitchen with wet hands, once a month at tax time. This sets density, target sizes, and contrast.
- **Character.** Two or three concrete words, such as "exact, calm, a little dry" or "quick, friendly, loud". Clean, modern, sleek, minimal, and premium are not allowed: they describe every template.
- **The bright spot.** The one or two places where the screen gets color and care, chosen from the content: the zone that needs attention, the chart that answers the question, the photo of the dish. Everything else stays quiet.
- **Signature.** One small detail only this product would have, used consistently. One, not five.

If the product has a real brand, the direction is built around it. In a light case, the direction is the existing brand; do not write a new one.

## Order of work

1. Tokens: color roles, type scale, spacing scale, radius, elevation, motion.
2. Shared components: buttons, list rows, cards, headers, empty and error states.
3. Screens, in the order of the findings: Critical, then Noticeable, then Minor.
4. Ask first items only after the user answers.

For visual work on a screen, go in passes and finish each one across the whole screen before the next. Spacing first, because everything reads differently once the rhythm is right. Copy before type, because the length of a headline decides its size. Motion last, because it should fit a screen that already works without it.

1. Spacing: one small scale, related things closer than unrelated ones, rows of one kind the same height
2. Color: semantic roles, one accent, color only where it means something
3. Icons: one set, one size, one stroke, the text color; emoji and decorative icons go
4. Copy: the product's nouns and verbs, errors with a cause and a next step, no hype, no invented claims
5. Type: platform styles or one scale, two weights, sentence case, tabular figures for numbers
6. Layout: content first, native structure, one primary action
7. Details: states, radius that nests, focus, pressed, empty, error, offline
8. Motion: what explains a change stays, what loops or decorates goes

## Rules of the fix

- Remove before adding. Most screens improve by losing containers, colors, captions, and copy.
- Keep frequently used controls, gestures, and URLs where users expect them. Ask before moving, removing, or redefining one.
- Keep business logic, data flow, and analytics unchanged.
- Ask before changing the navigation structure or the product's visual identity.
- Ask before adding a dependency. Use what the platform and the project already have.
- Never invent a metric, quote, logo, or testimonial. Ask whether a claim is real; if not, remove it and list it in the report.
- Mark placeholder content as placeholder instead of polishing it. Mock data looks plausible, never `123,456` or `[X]`.
- Keep the diff to the agreed screens and the shared code they need.
- Use the platform's building blocks before custom ones: [ios.md](ios.md), [android.md](android.md), [stacks.md](stacks.md), [web.md](web.md).

## Do not swap one default for another

The most common failed treatment takes a purple, sparkly screen and returns a white screen with gray-bordered cards, one blue accent, an icon in a tinted square on each row, and a lot of empty space. It is cleaner. It is also the default look of every model, and people recognize it at a glance. Read section 6 of [tells.md](tells.md) before you design anything.

A treated screen gets its character from the product, not from a style:

- **Content first.** The thing the user came for, their orders, their zones, their messages, gets the most space and the strongest type. Chrome, greetings, and section labels get less. If the after shows less real content than the before, look again.
- **The product's own nouns.** Headers name what is there ("Kitchen lights", "Due this week"), not a dashboard category ("Overview", "Quick actions").
- **Color with a job.** Keep the brand color. Give color to state and meaning (selected, overdue, offline, destructive), not to decoration. If the product has no brand color, ask before inventing one.
- **Quiet chrome, one bright spot.** Navigation, buttons, and labels stay quiet; the bright spot from the direction carries the color and the care.
- **Hierarchy from type and space first.** Size, weight, and grouping before containers, borders, and tints. A list is usually better than a stack of cards.
- **Native over bespoke.** A system list, sheet, or tab bar, or on the web a real button, link, dialog, and select, styled with the brand, beats a hand-built imitation.
- **Density that fits the use.** A tool used many times a day can be dense. Generous whitespace is a choice for a reason, not a default.

## The floor

Every changed screen meets these before you call it done. They do not bend.

- Touch targets at least 44pt on iOS and 48dp on Android, including padding and expanded hit areas such as `hitSlop`. On the web, at least 24 by 24 CSS pixels, 44 for primary touch targets.
- Contrast 4.5:1 for body text, 3:1 for large text and meaningful icons, in light and dark.
- Platform text styles or a named scale. Text follows the user's size setting or browser zoom and nothing clips at the largest size or 200%.
- Content and controls clear of the notch, Dynamic Island, home indicator, status bar, and keyboard. Backgrounds may run edge to edge.
- One primary action per screen, within thumb reach on a phone.
- Spacing from a small scale. Related items closer than unrelated ones.
- Semantic color roles: background, surface, text, secondary text, accent, destructive. Dark mode is a real palette, not an inversion.
- Native navigation: tabs for three to five peer destinations, push for drilling in, sheets for short side tasks; on the web, real links and a working back button.
- Icon-only controls labeled for screen readers. Logical focus order and a visible focus style. Reduce Motion honored. Color never the only signal.
- Pressed, hover where there is a pointer, focus, disabled, loading, empty, error, and offline states for everything you touched.
- On products that ship to several platforms, each platform's patterns. Share the brand, not every control.

## Waivers

A tell can stay when there is a real reason: the brand, a user need, a platform constraint. Record it under Accepted in `.unslop-anything/chart.md` with the reason, and list it under Waived in the report. A tell kept without a reason is not a waiver; it is a finding.

## Self-check before you hand it back

Answer each in one line in the treatment summary.

1. **Cover the logo.** Could the after screen belong to an unrelated product? If yes, it is not done.
2. **The neighbor test.** Would a competitor in the same category get this exact screen from the same request? If yes, change one decision and say which.
3. **Count the containers.** Did the number of cards, borders, and tinted backgrounds go down?
4. **Count the colors.** Does every color on screen carry meaning?
5. **Find the dots.** Every small colored dot, badge, and pill: what status does it show, and would a color-blind user get it?
6. **Find the task.** Is the top task's control in the same place or better, and reachable with one thumb or one Tab?
7. **Run the detector** on the changed files. Explain any hit you kept.
8. **The fresh look.** What did the fresh-context reviewer say, and what did you change because of it? If you could not start one, say so.
9. **Say what you did not check**, performance included. A check you did not run is not a pass.
