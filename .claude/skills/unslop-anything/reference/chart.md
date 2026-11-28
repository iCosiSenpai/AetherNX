# The chart

`.unslop-anything/chart.md` is the project's standing context. Every command reads it. `chart` writes it.

## Writing it

1. Infer everything you can from the code: stack, platforms, navigation structure, theme files, brand color and typeface, existing design system, analytics and ad SDKs.
2. Ask only for what code cannot tell you, in one message, at most four questions:
   - What do people open this app to do? The top one to three tasks.
   - Who are they, and where are they when they use it? (Driving, cooking, at a desk, one-handed on a train.)
   - Which parts of the look are the brand and must stay?
   - Anything off limits: screens, controls, flows owned by another team.
3. Write the file in the format below. Keep it under a page.

When it already exists, show what changed in the code since it was written and update only those lines.

## Format

```markdown
# Chart

Stack: <framework and version>
Platforms: <iOS, Android, iPad, tablets, foldables, web>
Visits: on

## Top tasks
1. <task, and the screen it starts on>

## Users and context
<one or two lines>

## Brand
- Color: <hex and where it comes from>
- Type: <faces and where they are used>
- Keep: <brand decisions that win over a tell, e.g. "the gradient comes from the app icon">

## Accepted
- <tell or rule id>: <why it stays, who decided, date>

## Off limits
- <screen or control>: <why>
```

## Accepted exceptions

When the user decides a tell stays, add it under Accepted with the reason. For detector rules, also add the rule id to `ignoreRules` in `.unslop-anything/config.json` if it applies project-wide, or an inline `unslop-anything-ignore <rule-id>` comment if it applies to one line. Do not re-flag accepted items in later visits.
