# Undertone design principles

How Undertone should look and behave, and how to judge a design before it ships. `DESIGN.md` lists
the tokens and components; this file says how to use them well. It draws on Apple's macOS 26
guidelines, classic product-design books and the practice of teams known for craft (sources at the
end), turned into rules for this app.

## What Undertone is for

People record a call, then read what was said. Everything else serves those two moments. The app
earns trust by being quiet, private and obviously in control of the microphone.

## The seven principles

### 1. Calm over clever

The app should need the least possible attention (Calm Technology). Granola's guiding line, "it
should lower your blood pressure", applies here too.

- Show state in the periphery: the menu bar icon and timer, not alerts.
- One notification per event that matters (a meeting starts, recording stopped by itself, a
  transcript is ready). Never more.
- Progress is informative, not alarming: steps and a percentage, no spinners without words.
- Hide machinery: model names, chunking, echo removal belong in Settings and the README, not on the
  main screens.

### 2. Native, a good Mac citizen

A "Mac-assed" app behaves like the Mac (Apple's four qualities: flexible, familiar, expansive,
precise).

- System controls, SF Pro, SF Symbols, the standard sidebar and toolbar. Custom drawing only where
  no system view fits.
- Every command lives in a menu with a shortcut; Settings opens with ⌘,; context menus on every
  meeting; drag a transcript out as a file.
- Active and inactive windows look different (selection turns grey when the window is not focused).
- Full keyboard navigation of the sidebar and transcript.
- Respect Reduce Motion, Reduce Transparency, Increase Contrast and the accent color setting.

### 3. Content first, controls float above it (macOS 26)

Apple's new design separates a functional layer of controls (Liquid Glass) from content.

- Glass is for navigation and controls only (toolbar, sidebar, floating buttons), never for
  transcript text or cards.
- Express hierarchy through layout and grouping, not background colors.
- Concentric shapes: an inner corner radius equals the outer radius minus the padding between
  them. Capsules for buttons and badges.
- Fewer, grouped toolbar items: related actions share one group; rarely used ones go to the More
  menu.

### 4. Built for reading

The transcript is the product, so it must read like good typography, not like a log.

- Line length 50–75 characters (Baymard; studies find about 55–66 best). SF Pro at 13 pt takes
  about 6.3 pt per character, so today's 760 pt column holds about 120 characters per line, twice
  the comfortable length. Use 15 pt transcript text in a column of about 540 pt (≈ 75 characters),
  or keep 13 pt in about 440 pt.
- Line height about 1.4–1.5 × the font size for transcript text.
- Speaker names and times are quieter than what was said: weight and color before size, then size.
- Long meetings need wayfinding: sticky speaker or time markers, search that jumps between matches,
  and a summary or outline at the top once summaries exist.

### 5. Privacy you can see

On-device processing is the main promise, so the interface shows it instead of claiming it.

- Ask for as little as possible, and only when needed (Apple: data minimization, on-device
  processing, transparency and control).
- Say where data goes at the moment it matters: "Stays on this Mac" while recording; "Only this
  transcript goes to Google Docs" before an export.
- Recording is never ambiguous: red dot and timer in the menu bar, a clear Stop, and the consent
  reminder before a recording.
- Every connection has a visible Disconnect.

### 6. Less, but better

Dieter Rams' rule, and Linear's practice of quality over metrics.

- Each screen has one primary action; at most one prominent button per view.
- Remove before adding: a new element must replace something or justify its space.
- Design in grayscale first, add color last; color carries meaning (red = recording, orange =
  problem, green = done, accent = interactive), never decoration.
- Polish is part of the feature: alignment, spacing on the 2–4 pt grid, optical alignment of icons,
  monospaced digits for changing numbers. Beautiful interfaces are also perceived as easier to use
  (aesthetic-usability effect).

### 7. Clear feedback for every action

From Norman's *The Design of Everyday Things*: visible signifiers, immediate feedback and a simple
conceptual model.

- Respond within 400 ms (Doherty threshold); longer work shows progress at once.
- Every action has a visible result: copied, saved to Docs (with a link), renamed.
- Errors say what happened and what to do, with the button that does it.
- The conceptual model stays simple: a meeting is a recording plus its transcript, kept as files in
  one folder.

## Onboarding and permissions

The welcome flow is the first impression; most people decide here whether to trust the app.

1. **Value first.** One screen that says what Undertone does and why it is private, before any
   request.
2. **Permissions in context.** Explain the benefit, then show the system dialog. Microphone and
   system audio right before the first recording; calendar and notifications when the user turns on
   the calendar. Never all at once on launch.
3. **Always a way back.** If a permission is denied, show what is missing and a button to the right
   pane of System Settings. Every optional step can be skipped.
4. **Short.** Three to five steps, with progress shown. Teach the rest in context (empty states,
   first-use hints) rather than in a tour.
5. **Honest opt-ins.** The optional email for feedback: off by default, in plain words: "I'm the
   only developer. Leave your email if I may ask you now and then how Undertone works for you. No
   newsletters, unsubscribe any time." Privacy policy link next to it.

## Motion

- Purposeful only: show where something came from or went, or confirm an action.
- Fast and decelerating: ease-out, 150–250 ms; nothing slower than 300 ms except large window
  transitions.
- No animation on actions repeated many times a day (selecting rows, typing, opening menus).
- The recording dot's slow pulse is the one ambient animation; everything else is still.
- With Reduce Motion on, replace movement with a cross-fade.

## Empty states and errors

- Empty states teach the next step with one action (No Meetings Yet → Start Recording).
- Errors are specific, calm and actionable; never just "Something went wrong".
- Long operations survive quitting and say so ("You can close this window").

## Accessibility

- Text contrast at least 4.5:1, large text 3:1, in both appearances.
- Never color alone: statuses also have an icon or a word.
- Every icon-only button has a label and a tooltip.
- VoiceOver reads a transcript line as "Speaker, time, text".

## Review checklist

Before a UI change is done:

- [ ] Uses tokens and components from `DESIGN.md`; new ones are added there and in Figma.
- [ ] Light and Dark; window focused and unfocused; Reduce Motion and Increase Contrast.
- [ ] One primary action per view; nothing that could be removed without loss.
- [ ] Text column within 50–75 characters where people read.
- [ ] Every action gives feedback within 400 ms; errors offer a way out.
- [ ] Menu item and shortcut for every new command.
- [ ] Privacy and recording state stay unambiguous.
- [ ] Spacing on the grid, icons optically aligned, digits monospaced.
- [ ] Looked at in the real app, not only in Figma.

## Sources

- Apple, [Get to know the new design system (WWDC25)](https://developer.apple.com/videos/play/wwdc2025/356/);
  [notes](https://wwdcnotes.com/documentation/wwdc25-356-get-to-know-the-new-design-system/);
  [Create with Swift on hierarchy, harmony, consistency](https://www.createwithswift.com/liquid-glass-redefining-design-through-hierarchy-harmony-and-consistency/)
- Apple, [Designing for macOS (HIG)](https://developer-rno.apple.com/design/human-interface-guidelines/platforms/designing-for-macos);
  [Build trust through better privacy (WWDC20)](https://www.wwdcnotes.com/notes/wwdc20/10676)
- [What makes an app feel right on the Mac](https://coyotetracks.org/blog/app-feel-on-mac/);
  [John Gruber on Mac apps](https://daringfireball.net/2020/11/sketch_mac_app_mac_apps);
  [Sketch: why a truly native Mac app](https://sketch.com/blog/part-of-your-world-why-we-re-proud-to-build-a-truly-native-mac-app);
  [Mac-assed SwiftUI app in 2026](https://hn.jakechampion.name/reader/https://pfandrade.me/blog/mac-assed-swiftui-app/)
- Granola: [Inside Granola's design philosophy (Sam Stephenson)](https://www.cognitiverevolution.ai/calm-ai-for-crazy-days-inside-granola-s-design-philosophy-with-co-founder-sam-stephenson/);
  [Chris Pedregal on Granola](https://nesslabs.com/granola-featured-tool)
- Linear: [Inside Linear: taste, craft and focus (Karri Saarinen)](https://www.lennysnewsletter.com/p/inside-linear-building-with-taste)
- Amber Case, [Principles of Calm Technology](https://calmtech.institute/calm-tech-principles)
- Adam Wathan and Steve Schoger, *Refactoring UI* ([review](https://dev.to/updivision/book-review-refactoring-ui-by-adam-wathan-steve-schoger-2f7m))
- Don Norman, *The Design of Everyday Things* ([summary](https://medium.com/the-oxford-comma/book-summary-the-design-of-everyday-things-by-donald-norman-ad8c508c7295))
- Jon Yablonski, *Laws of UX* ([lawsofux.com](https://lawsofux.com/index.md))
- Dieter Rams, [Ten principles for good design](https://principles.design/examples/ten-principles-of-good-design)
- Rauno Freiberg, [Invisible details of interaction design](https://uiuxshowcase.com/resources/invisible-details-of-interaction-design-by-rauno-freiberg)
- Baymard Institute, [Line length readability](https://baymard.com/blog/line-length-readability)
- Permission priming: [Appcues](https://www.appcues.com/product-adoption-academy/mobile-app-onboarding-101/priming-users-to-grant-mobile-apps-permission),
  [Hopper case study](https://growth.design/case-studies/hopper-permission-requests-ux)
- [Privacy Starts with UI (2026)](https://arxiv.org/html/2601.13342v1)
