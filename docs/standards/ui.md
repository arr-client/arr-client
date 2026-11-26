# UI standard

The app should feel like a well-made Android app, not a template. Reviewers check pull requests with
UI changes against this page and ask for screenshots in light and dark.

## Foundation

- Material 3 components. Build a custom widget only when no component fits, and put it in
  `packages/ui` if a second screen needs it.
- All colour, type and shape come from the theme. No hex values or text styles in screens.
- Dynamic colour is optional for the user, so nothing may rely on a particular hue.

## Layout

- Spacing in steps of 4: 4, 8, 12, 16, 24, 32.
- One screen margin (16 on phones, 24 from 600 dp wide).
- Decide layouts from available width, never from device type.
- Prefer lists and spacing to nesting cards inside cards.

## Hierarchy and content

- Artwork and titles lead; metadata is quieter. One primary action per screen.
- State is shown with an icon or text as well as colour.
- Numbers use the user's locale; sizes, speeds and dates are formatted one way, by shared helpers.
- Missing data is left out, not shown as "N/A" or a made-up value.

## Wording

- Plain, short and specific. Buttons say what they do: "Delete movie", not "OK".
- Errors say what happened and what to do next.
- Sentence case. No emoji, exclamation marks or filler such as "Oops".

## Motion and feedback

- Use the platform's transitions; respect the system's reduced-motion setting.
- Show skeletons or progress for waits over about 300 ms; never block the whole app for one service.

## Avoid

- Decorative gradients, glows and glass effects.
- Icons that decorate without meaning, and mixing icon styles.
- Badges or highlights on things that are not new or actionable.
