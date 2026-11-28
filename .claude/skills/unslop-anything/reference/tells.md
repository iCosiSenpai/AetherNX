# The tells

Each tell names what to look for. Where the detector can see it in code, its rule id is in brackets. A tell without an id needs eyes on the running app or judgment about the product.

Check in this order. The order follows what users complain about, not what is easy to spot.

This catalog covers native and web. Section 3 is for native apps only; web apps and websites have their own floor and tells in [web.md](web.md).

## 1. User friction

Users complain about these far more than about how an app looks.

- Frequently used controls moved, removed, or buried in settings
- A familiar gesture given a new meaning
- Core tasks taking extra steps or hidden several screens deep
- AI features intercepting a core task, or taking the best spot on screen with no way to dismiss them. The sparkle button in the toolbar where search used to be. [`sparkle-icon`]
- Ads, promos, rating prompts, and popups that interrupt a task
- Upsell or destructive icons placed next to a common tap target
- Common actions out of thumb reach
- Controls that look right but do nothing, respond late, or trigger the wrong item
- Key actions clipped, overlapped, or unreachable on some screen sizes
- Read, unread, selected, or active states that are hard to tell apart, especially in dark mode
- Layouts that lose most of the screen to padding or chrome

## 2. Truthfulness

The app says something that is not so.

- Failed loads shown as empty states ("No orders yet" when the request failed)
- Totals computed from one page of results
- "Recent" lists that are not recent, "live" data that is cached
- Buttons that go somewhere other than their label says
- Stat tiles with invented or placeholder numbers [`invented-stat`]. Real data in a tile is not a tell.
- Social proof and speed claims nobody supplied: "Trusted by 10,000+ teams", "10x faster", logo walls, testimonials [`unverified-claim`]
- Trust or privacy claims the code contradicts, such as "no tracking" beside an ad SDK
- Wrong or approximate logos

## 3. Website in a phone (native apps)

- Hamburger menu in place of tabs for the few top destinations [`drawer-nav`]
- Marketing hero, feature grid, or footer inside the app
- Breadcrumbs, wide tables, or hover-dependent controls [`hover-only`]
- Hand-built back buttons or navigation bars that lose native gestures [`back-gesture`]. Judge custom tab bars on hierarchy, labels, and pressed states, not on being custom.
- Centered modals for tasks that belong in a sheet or a pushed screen
- Tiny text links as the main way to act
- Long forms on one screen with no sensible field order or input types

## 4. Interaction and states

- No pressed state on tappable things
- Only the happy path: missing loading, empty, error, and offline states
- A spinner for everything, including content whose shape is known
- Keyboard covers the focused input [`keyboard-cover`], wrong keyboard type, no submit action on the keyboard, no easy way to dismiss it
- Content under the notch, home indicator, or system bars [`safe-area-off`]
- Swipe back or predictive back broken [`back-gesture`]
- Long lists without pull to refresh where freshness matters, or without virtualization [`unvirtualized-list`]
- Every element fading and sliding in on mount, or animation that blocks input
- Motion by habit: transitions on every property [`transition-all`], cards that grow on hover [`hover-scale`], dots and badges that pulse forever [`decorative-pulse`]
- Haptics on everything, or none on moments that deserve confirmation
- Fixed heights or fixed text sizes that clip when the user enlarges text [`fixed-text-size`]

## 5. Looks generated: the old default

The 2023 look. Easy to spot, and most models have learned to avoid it unless told otherwise.

- Purple, indigo, or blue-to-pink gradients on heroes, buttons, or backgrounds [`slop-gradient`]
- The project template's color left as the theme: Flutter's `Colors.deepPurple` seed, Android Studio's `Purple40` [`template-theme`]
- Gradient text [`gradient-text`], glow shadows [`glow-shadow`], decorative blobs, glass on everything [`glass-everywhere`]
- Sparkle icons [`sparkle-icon`], or emoji standing in for icons [`emoji-icon`]
- Cards inside cards [`nested-cards`]
- Pill badges on things that are not statuses
- "Unlock your potential" copy (see Copy below)

## 6. Looks generated: the new default

The look that replaced the purple one. It reads as tasteful and calm, and it is just as generic. A fix that lands here has swapped one template for another. Check every after screenshot against this list.

- Everything on white or off-white, every group in a rounded card with a 1px gray border and a soft shadow, one radius everywhere
- One blue or black accent, with nothing else in the palette carrying meaning
- An icon in a tinted rounded square at the start of every row [`icon-tile`]
- A small colored dot beside labels that carries no status the user acts on [`status-dot`]. A dot that marks unread or online, has a text or shape backup, and is consistent across the app is a status, not a tell.
- Section headers like "Overview", "Quick actions", "Recent activity", in small gray caps or with letter spacing [`tracked-caps-label`]
- Large empty margins presented as calm, so the content a user came for gets less of the screen than the chrome
- Gray secondary text under every title, repeating it in other words
- A stat row of three numbers at the top of every main screen
- One font size and weight doing every job, or a web font replacing good system type for no brand reason
- Identical spacing everywhere, so nothing is grouped
- Centered text where a left-aligned list would read faster
- Low-contrast gray text on tinted backgrounds
- Filler captions, annotations, and callouts that add nothing
- Duplicate buttons doing the same job

The test for this section: cover the logo and the app name. Could this screen belong to a banking app, a fitness app, and a to-do app equally well? Then it is the default, however clean it looks.

## 7. Copy

- "Unlock your potential", "seamless", "effortless", "supercharge", "all in one place" [`buzzword-copy`]
- "Welcome back!" taking the best space on the screen [`welcome-back`]
- "Oops! Something went wrong" with no cause and no next step [`oops-error`]
- Subtitles that repeat the title
- Exclamation marks as personality
- Vague buttons such as "Submit" where a verb would say what happens [`vague-button`]

## 8. Performance

You can only suspect these from code. See [performance.md](performance.md).

- Lists that render every row up front [`unvirtualized-list`]
- Heavy work on launch, on the main thread, or in a scroll or typing path
- Full-size images decoded for thumbnails
- Lag while scrolling, typing, or switching tabs: needs profiling on a real device

## Using the detector

`node <skill-dir>/scripts/detect.js <dirs> --json` runs every rule. `--list-rules` prints each rule with its fix. Rules fire on patterns, so:

- A hit is a lead. Open the file and confirm it is real in this product before you report it.
- No hit means nothing. Most of sections 1, 2, and 6 cannot be seen in code at all.
- Silence a confirmed false positive with `// unslop-anything-ignore <rule-id>` on that line or the line above. In XML and HTML files, where `//` is not a comment, use `<!-- unslop-anything-ignore <rule-id> -->` instead. In CSS, where `//` is not a comment either (the line would merge into the next selector and the browser would drop that rule), use `/* unslop-anything-ignore <rule-id> */`. Or list the rule under `ignoreRules` in `.unslop-anything/config.json` when the chart accepts it project-wide.
