# The report

## Severity

- **Critical:** a user can't finish a task, gets wrong information, or can't read or reach a primary control.
- **Noticeable:** a task is slower or more confusing, or the screen clearly looks generated.
- **Minor:** polish that doesn't affect the task.
- **Ask first:** a fix that would change navigation, visual identity, monetization, or a frequently used control.

Keep Minor short. A long tail of polish buries the findings that matter. If there are more than eight, list the top eight and give a count for the rest.

## Scores

Score each dimension 0 to 4 from what you saw. A score needs a reason: the worst finding in that dimension, or what earned the 4.

| Dimension | Asks | 0 | 4 |
|---|---|---|---|
| Task path | Can people do what they came to do, fast, with controls where they expect them and nothing in the way? | Core task blocked or interrupted | Core task direct, thumb reachable, uninterrupted |
| Truth | Do labels, numbers, and states say what is true? | Errors shown as empty, invented data | Every number and state is real and labeled |
| Native fit | Navigation, gestures, controls, and safe areas as the platform expects. On the web: real buttons and links, URLs and back that work, focus, zoom, and native form controls | A website in a phone, or a web page that breaks the web | A fluent user trusts every screen |
| States and input | Loading, empty, error, offline, pressed, keyboard | Happy path only | Every state designed and reachable |
| Access | Targets, contrast, text scaling, screen reader labels and order | Unusable with a screen reader or large text | Labeled, ordered, scales cleanly |
| Specificity | Does it look like this product, not a template, old or new? | Could be any app; generated tells throughout | Built from this product's content and voice |

Total out of 24:

- **21 to 24: Discharged.** Minor polish.
- **16 to 20: Outpatient.** Address the weak dimensions.
- **11 to 15: Admitted.** Significant work.
- **0 to 10: Intensive care.** Start with Critical and Task path.

Performance is not scored. It gets its own line (see [performance.md](performance.md)).

When you reviewed from code only, mark Native fit, States and input, and Access as estimated with a `~` before the score.

## Format

```text
Dr. Unslopovich's diagnosis
Verdict: <one dry sentence>
Stack: <stack and platforms>
Reviewed: <screens, top tasks, and whether from a running app or code only>
Score: <total>/24 <band>  Task path <n> · Truth <n> · Native fit <n> · States <n> · Access <n> · Specificity <n>
Performance: <"Not profiled." and the static leads, or what was profiled, how, and the numbers>

Critical
- <file:line> <what is wrong and who it hurts> -> <specific fix>

Noticeable
- <file:line> <what is wrong> -> <specific fix>

Minor
- <file:line> <what is wrong> -> <specific fix>

Ask first
- <file:line> <what is wrong> -> <proposed fix and what it would change for users>

Waived
- <rule or tell> kept because <reason>, recorded in the chart

Worth keeping
- <what already works and should survive the treatment>

Not checked
- <anything you could not verify, always including performance unless profiled>
```

Leave out empty sections, except Not checked.

If the screen is healthy, the verdict says so and the report is short. A report that invents problems to fill its sections is its own kind of slop.

## The verdict line

One sentence, dry, specific to this app. It names the worst thing, not the funniest. It is never cruel about the person and never about AI use; the patient is the screen.

Good: "The order button moved, the list stutters, and the dashboard reports numbers no one measured."

Bad: "Classic AI slop." It is generic, which is the thing we are treating.

## After a treatment

List what changed by screen. Capture before and after screenshots of the same screen, same data, same device, same appearance, when you can. Then run the self-check in [treatment.md](treatment.md) and give the new score.

## Saving the visit

Write the report to `.unslop-anything/visits/<YYYY-MM-DD-HHmm>-<scope>.md`, with the local time in 24-hour form and the scope as a short slug of the screens ("home", "checkout-flow"). If that file already exists, add `-2`, `-3`, and so on before `.md`; never overwrite a visit. File names sort by time, so `follow-up` reads the last file for the same scope in name order and adds a line per dimension: `Task path 2 -> 3`. Skip saving if `.unslop-anything/chart.md` says `visits: off`.
