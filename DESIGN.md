# Undertone design system

The single reference for Undertone's interface. Every UI change starts here: pick tokens and
components from this file (and the Figma file it describes), and update both when something new is
needed.

- **Figma:** [Undertone Design System](https://www.figma.com/design/iWTtCYT2UFRhcUCHLORnOp)
  (pages: Cover, Foundations, Atoms, Rows, Cards & Panels, Controls, Screens, Redesign, Onboarding)
- **State:** the app follows the Redesign page (see [Redesign](#redesign)). The other pages hold
  the first version's components; those the redesign replaced are marked "replaced" below and stay
  in Figma only as a record. Changes to the look should be made here first and then in code.
- **Platform:** native macOS (SwiftUI, macOS 15+), following Apple's Human Interface Guidelines.
  System controls come from Apple's macOS 26 Figma library.

## Principles

The full guide, with onboarding, motion, reading, accessibility and a review checklist, is in
[DESIGN-PRINCIPLES.md](DESIGN-PRINCIPLES.md). In short:

1. **Native first.** Use system controls, system colors and SF Pro text styles. Draw a custom view
   only when no system view fits (speaker badges, level meter, status marks).
2. **Semantic tokens, never raw values.** Colors, spacing and radii come from the tokens below. A new
   value means a new token, added in Figma and here, not a literal in a view.
3. **Both appearances.** Every screen must work in Light and Dark. In Figma, switch a frame's
   `Color` mode; in SwiftUI, use the semantic colors listed here and they follow the system.
4. **Red means recording.** `status/recording` is reserved for recording and stopping. Destructive
   actions use the system role (`role: .destructive`), not a red tint.
5. **Calm by default.** One prominent button per view, secondary text for metadata, no decoration
   that does not carry information.

## Foundations

### Color

Figma collection `Color`, modes `Light` and `Dark`. Values follow Apple's macOS 26 palette. The
SwiftUI column is what to write in code.

| Token | Light | Dark | SwiftUI | Use |
|---|---|---|---|---|
| `bg/content` | `#FFFFFF` | `#1E1E1E` | `Color(nsColor: .textBackgroundColor)` | Transcript and detail area |
| `bg/window` | `#ECECEC` | `#2D2D2D` | `Color(nsColor: .windowBackgroundColor)` | Settings, sheets, menu bar panel |
| `bg/sidebar` | `#E8E8EA` | `#2A2A2D` | sidebar material (`List` in a split view) | Sidebar, translucent in the app |
| `bg/toolbar` | `#F4F4F5` | `#2F3033` | window toolbar | Unified title bar and toolbar |
| `bg/card` | black 5 % | white 5 % | `.fill.quaternary` | Cards and grouped boxes |
| `bg/field` | `#FFFFFF` | white 6 % | `TextField(.roundedBorder)` | Text fields, bordered buttons |
| `bg/selection` | `#0088FF` | `#0091FF` | list selection, window focused | Selected row |
| `bg/selection-inactive` | black 10 % | white 10 % | list selection, window not focused | Selected row |
| `bg/warning` | orange 12 % | orange 12 % | `.orange.opacity(0.12)` | Notice banner |
| `bg/recording` | red 12 % | red 12 % | `.red.opacity(0.12)` | Halo behind the recording icon |
| `label/primary` | black 85 % | white 85 % | `Color.primary` | Main text |
| `label/secondary` | black 50 % | white 55 % | `Color.secondary` | Times, captions, metadata |
| `label/tertiary` | black 25 % | white 25 % | `.tertiary` | Transcript timestamps |
| `label/quaternary` | black 10 % | white 10 % | `.quaternary` | Pending step circles, progress track |
| `label/on-accent` | `#FFFFFF` | `#FFFFFF` | `Color.white` | Text on accent, selection, badges |
| `separator` | black 10 % | white 10 % | `Divider()`, `.separator` | Dividers, card borders |
| `accent` | `#0088FF` | `#0091FF` | `Color.accentColor` | Links, the "Me" speaker, prominent buttons |
| `status/recording` | `#FF383C` | `#FF4245` | `Color.red` | Recording dot, record and stop buttons |
| `status/warning` | `#FF8D28` | `#FF9230` | `Color.orange` | Failures, notices, reconnecting |
| `status/success` | `#34C759` | `#30D158` | `Color.green` | Done checks, NOW badge, "Happening now" |
| `meter/low`, `meter/mid`, `meter/high` | green, yellow, red | same, dark variants | `.green`, `.yellow`, `.red` | Level meter segments |
| `meter/off` | black 9 % | white 10 % | `Color.secondary.opacity(0.18)` | Unlit meter segment |
| `speaker/1`…`speaker/8` | orange, purple, teal, pink, green, indigo, brown, cyan | dark variants | `[.orange, .purple, .teal, .pink, .green, .indigo, .brown, .cyan]` | Other speakers, in order of first appearance; "Me" uses `accent` |
| `attendee/1`…`attendee/4` | blue, purple, pink, teal | dark variants | `[.blue, .purple, .pink, .teal, …]` | Attendee avatars |
| `calendar/default` | `#6155F5` | `#6D7CFF` | `event.color` | Example only: real events use their calendar's color |

### Spacing and radius

Figma collection `Layout`. The app uses the values directly in SwiftUI (`spacing:`, `.padding()`).

| Token | Value | Typical use |
|---|---|---|
| `space/2` … `space/36` | 2, 4, 6, 8, 10, 12, 14, 16, 18, 22, 24, 28, 36 | 2–4 inside text stacks, 8–12 between row elements, 14 panel padding, 18 card padding, 22–28 between page sections, 36 sheet padding |
| `radius/dot` | 2.5 | Calendar color dot |
| `radius/control` | 6 | Regular buttons, sidebar selection |
| `radius/banner` | 8 | Notice banner, large buttons, search field |
| `radius/card-small` | 10 | Menu bar card, settings groups |
| `radius/card` | 12 | Event card, level box, windows |
| `radius/full` | 999 | Capsules and circles (badges, dots, avatars) |

Content width: transcript and event pages use the 600 pt reading column (`readingColumn()`), with
28 pt side padding. Sidebar: 240–400 pt, ideal 280. Menu bar panel: 320 pt. Settings: 540 pt.
Onboarding sheet: 560 pt.

### Typography

SF Pro, copied from Apple's macOS 26 text styles. Use the SwiftUI text style, not a fixed size.

| Figma style | Font | SwiftUI | Where |
|---|---|---|---|
| Large Title Emphasized | SF Pro Bold 26/32 | `.largeTitle.weight(.bold)` | Meeting and event titles, Welcome |
| Title 1 / 2 / 3 | Regular 22, 17, 15 | `.title`, `.title2`, `.title3` | Recording screen title, subtitles |
| Headline | Bold 13/16 | `.headline` | Card titles, section titles |
| Body / Body Emphasized | 13/16 | `.body` | Transcript text, rows |
| Callout / Callout Emphasized | 12/15 | `.callout` | Meta rows, speaker names, banners |
| Subheadline / Emphasized | 11/14 | `.subheadline` | Sidebar subtitles and section headers |
| Footnote | 10/13 | `.footnote` | Consent note, form footers |
| Caption 1 / Caption 2 Emphasized | 10/13 | `.caption`, `.caption2.weight(.semibold)` | Timestamps, badge text |
| Control | SF Pro Medium 13/16 | system control font | Button and toolbar labels |
| Timer/Large | SF Pro Rounded Light 52 | `.system(size: 52, weight: .light, design: .rounded)` | Elapsed time while recording |
| Timer/Compact | SF Pro Rounded Medium 15 | `.system(.title3, design: .rounded).weight(.medium)` | Elapsed time in the menu bar panel |

Numbers that change (times, percentages) use `.monospacedDigit()`.

### Icons

SF Symbols only, `Image(systemName:)`. In Figma each symbol is a component `Icon/<name>` (16 pt
box) and is swapped through the `Icon` property of buttons and rows. Symbols in use: `waveform`,
`waveform.slash`, `record.circle`, `record.circle.fill`, `stop.fill`, `mic.fill`,
`speaker.wave.2.fill`, `calendar`, `calendar.badge.plus`, `clock`, `exclamationmark.triangle.fill`,
`checkmark.circle(.fill)`, `circle`, `xmark`, `video(.fill)`, `gearshape`, `power`, `macwindow`,
`magnifyingglass`, `square.and.arrow.up`, `doc.on.doc`, `doc.text`, `ellipsis.circle`,
`person.crop.circle`, `person.2`, `info.circle`, `sidebar.left`, `text.bubble`, `folder`,
`arrow.clockwise`, `trash`, `lock.shield`, `arrow.triangle.2.circlepath`. The menu bar's
`waveform.badge.ellipsis` (processing) is missing from Figma's SF font, so it is not drawn there.

## Components

Each Figma component maps to one SwiftUI view. Variants are the states the view can be in;
properties are what an instance can change.

### Atoms (`Sources/MeetNotes/Components.swift`, `EventViews.swift`)

| Figma | SwiftUI | Variants / properties | Notes |
|---|---|---|---|
| Speaker Badge | replaced by Transcript Turn | Color: Me, Speaker 1–8 · Initial | 24 pt circle, gradient fill in code, caption semibold white |
| Recording Dot | `RecordingDot` | Size: 8, 10 | Pulses opacity 1 → 0.35 every 0.9 s |
| Now Badge | replaced: Event Row says "Now · until 11:25" in green | — | Green capsule, uppercase caption2 |
| Calendar Dot | `EventRow`, `EventDetail` | — | 9 pt, radius 2.5, calendar color |
| Progress Bar | `ProgressView(value:)` | — | System linear progress |
| Spinner | `ProgressView()` | Size: Small, Mini | System circular progress |
| Status Mark | `StatusMark` | Status: Recording, Processing, Queued, Failed, Not Transcribed | Ready and No speech show nothing |
| Level Meter | replaced by Track Bar | Level: Silent, Quiet, Normal, Loud | 18 segments 4×12, spacing 2, dB scale |
| Attendee Avatar / Stack | `AttendeeStack` | Color 1–4 · Initial · Show More | Overlap −6, 1.5 pt ring, "+N" |

### Rows (`MeetingsView.swift`, `EventViews.swift`, `MeetingDetail.swift`, `Components.swift`)

| Figma | SwiftUI | Variants / properties | Notes |
|---|---|---|---|
| Sidebar Section Header | `Section("…")` in the sidebar `List` | Title | Up Next, Today, Yesterday, Previous 7/30 Days, month |
| Meeting Row | `MeetingRow` | State: Default, Selected, Selected Inactive · Title, Subtitle, Show Status | One-line title and subtitle; untitled meetings use secondary |
| Event Row | `EventRow` | Trailing: Time, Now, Recording, Recorded × State · Title, Time | Redesign: calendar color bar, title, "Now · until 11:25" or "Tomorrow 14:00–14:45", red record button while it runs (see Up Next Card) |
| Sidebar Action | borderless `Button` in `UpNextRows` | Label, Icon | Connect Google Calendar…, Connect macOS Calendar…, Show All |
| Transcript Segment | replaced by Transcript Turn | Speaker: Me, Speaker 1–3 · Name, Time, Text | Name opens the rename menu; search matches get a yellow highlight |
| Processing Step | `ProcessingSteps` | State: Done, Current, Pending · Step | Seven steps, see `ProcessingStep` |
| Track Level | replaced by Track Bar | Track: Microphone, Call Audio | 130 pt label column, then Level Meter |

### Cards & Panels

| Figma | SwiftUI | Notes |
|---|---|---|
| Notice Banner | `NoticeBanner` | Message, Show Settings Link; orange 12 % background, radius 8 |
| Meeting Header | `MeetingHeader` | Redesign: Display title (a text; click to rename), meta line, attendees and Privacy Chip |
| Detail Section | replaced by `EventDetail.section` (subheadline title) | Headline title, content with 6 pt spacing |
| Event Card | replaced: the event page has Record and Join under the title | Record changes to Stop / Open Transcript |
| Suggested Event Card | replaced by Up Next Card (`UpNextCard`) | Menu bar; "Happening now" (green) or "Starting soon" |
| Processing Row | `ProcessingRow` | Menu bar transcription progress |
| Menu Bar Footer | `MenuBarFooter` | Open Undertone, Settings, Quit |
| Empty State | `ContentUnavailableView` | Title, Description, Icon, Show Action |
| Settings Row | `LabeledContent` / `Toggle` in `Form(.grouped)` | Trailing: Value, Toggle, Button, Status |
| Settings Section | `Section { } header: footer:` | Card radius 10, rows divided by 0.5 pt lines, footer right-aligned |
| Welcome Feature | replaced by Onboarding Row | |
| Setup Row | replaced by Onboarding Row | |
| Model Download Progress | `ModelDownloadProgress` | Bar + caption |

### Controls

| Figma | SwiftUI | Notes |
|---|---|---|
| Button | `Button` | Style: Prominent Red (`.borderedProminent.tint(.red)`), Prominent (`.borderedProminent`), Bordered (default), Borderless, Link × Size: Regular (24), Large (30, `.controlSize(.large)`) × State: Default, Disabled (45 %). Label, Show Icon, Icon |
| Toolbar Button | `RecordToolbarButton` | Redesign: red capsule "Record"; while recording, a red Stop capsule with the time, hidden on the recording's own page |
| Search Field | `.searchable(placement: .sidebar)` | Drawn on our tokens so it follows Light/Dark |
| Text Field | `TextField(.roundedBorder)` | Meeting title in the menu bar panel |
| Switch | `Toggle` | Instance of Apple's macOS 26 Switch |

## Screens

On the Screens page, built only from component instances: Main Window — Transcript (Light and
Dark), Menu Bar Panel — Idle, Menu Bar Panel — Recording, Recording View, Event Detail, Settings —
Google, Welcome Sheet. Frames set the `Color` mode (and Apple's `Appearance` mode for Apple
controls) to switch appearance.

## Redesign

The Redesign page applies [DESIGN-PRINCIPLES.md](DESIGN-PRINCIPLES.md) to the main screens, and
the app follows it. It reuses the tokens and components above and adds the ones below.

Liquid Glass comes from the system: the app is built against the macOS 26 SDK
(`scripts/build-app.sh` records the real SDK version in the binary, since SwiftPM records the
deployment target and macOS would then draw the old look). On macOS 15 the same code shows the
classic sidebar and toolbar.

### What changes

- **Floating glass sidebar.** The sidebar is a glass panel inset 8 pt inside the window
  (`radius/panel`), not a full-height column; the reading area runs underneath it. Window corners
  use `radius/window`. In SwiftUI this is the macOS 26 `NavigationSplitView` sidebar with the
  system glass; do not draw it by hand.
- **Toolbar as glass groups.** No window title (`.toolbar(removing: .title)`). A flexible
  `ToolbarSpacer` keeps the actions on the right; Record is its own red capsule, then Share, Copy
  and Google Docs share one group, and a fixed spacer sets More apart.
- **Transcript as a document.** 15 pt text with 23 pt line height in a 540 pt text column (about 70
  characters per line), times in a 44 pt gutter on the left, speaker as a colored dot plus name
  above each turn. The page column is 600 pt and centered in the reading area: `readingColumn()`,
  with `Gutter.inset` (60 pt) before the header so titles line up with the text.
- **Header.** Display title, a meta line (date, start time, length), attendees and the Privacy Chip.
- **Recording.** The detail area shows only the recording: status, a hero timer, the meeting title,
  two track bars and one Stop button, with the Privacy Chip and "The transcript is ready a few
  minutes after you stop." The toolbar keeps only More. The sidebar gets a Now section with the
  meeting being recorded.
- **Menu bar panel.** A 320 pt glass panel. Idle: Up Next cards, then a bordered New Recording
  button; the red record button on the Now card is the only red control. Recording: status and
  compact timer, title, track bars, a full-width Stop button, Privacy Chip, footer.
- **Upcoming event.** Same page layout as a transcript: Display title, meta line, Start Recording
  (red capsule) and Join (bordered; "Join Google Meet", "Join Zoom", "Join Teams" or "Join Call"),
  then People, Location, From the Invite (transcript text style) and a Recording section with the
  Privacy Chip and the consent note. Figma shows "Record When It Starts"; the app has no scheduled
  start yet, so the button says Start Recording and the start notification offers Record.

### New tokens

| Token | Light | Dark | SwiftUI | Use |
|---|---|---|---|---|
| `bg/canvas` | `#F5F5F7` | `#141416` | `.windowBackgroundColor` | Behind panels |
| `bg/reading` | `#FFFFFF` | `#1C1C1E` | `.textBackgroundColor` | Reading area (transcript, event) |
| `material/glass` | white 55 % | `#3A3A3E` 42 % | `.glassEffect()` / system sidebar | Figma stand-in for Liquid Glass |
| `material/glass-edge` | white 75 % | white 12 % | part of the system glass | 0.5 pt inner edge on glass |
| `bg/selection-soft` | accent 14 % | accent 28 % | sidebar selection on glass | Selected sidebar item |
| `bg/chip` | black 5 % | white 7 % | `.fill.quaternary` | Privacy Chip, small tags |
| `label/privacy` | `#248A3D` | `#30D158` | `Color.green` | Privacy Chip text and icon |
| `radius/window` | 20 | | system window shape | Window corners |
| `radius/panel` | 14 | | `.rect(cornerRadius: 14)` | Glass sidebar, menu bar panel |
| `space/40`, `space/56` | 40, 56 | | | Gaps around the hero timer, page margins |

Text styles:

| Figma style | Font | SwiftUI | Where |
|---|---|---|---|
| Display | SF Pro Bold 30/36, −0.4 | `Font.display` | Page titles |
| Transcript | SF Pro Regular 15/23 | `Font.transcript` + `.lineSpacing(5)` | Transcript and invite text |
| Transcript Speaker | SF Pro Semibold 13/16 | `.callout.weight(.semibold)` | Speaker name above a turn |
| Gutter Time | SF Pro Regular 11/16 | `.caption.monospacedDigit()` | Times in the left gutter |
| Timer/Hero | SF Pro Rounded Light 64/72, −1 | `Font.heroTimer` | Elapsed time while recording |

Effect styles: **Glass/Regular** (Figma `GLASS` effect plus a soft 18 pt shadow; in code it is the
system glass) and **Shadow/Window** (two shadows; in code the system window shadow).

### New components

| Figma | Variants / properties | SwiftUI |
|---|---|---|
| Privacy Chip | Label | `PrivacyChip` |
| Record Capsule | State: Idle, Recording × Size: Regular, Large | `.borderedProminent.tint(.red)` with `.buttonBorderShape(.capsule)` |
| Glass Group | Icon 1–3, Show 2, Show 3 | `ToolbarItemGroup` (the system draws the glass) |
| Sidebar Item | State: Default, Selected · Title, Meta, Show Status | `MeetingRow` on the glass sidebar |
| Up Next Card | When: Later, Now · Title | `UpNextCard` in the menu bar panel; `EventRow` in the sidebar (no card background there) |
| Transcript Turn | Speaker: Me, Speaker 1–3 · Name, Time, Text | `TranscriptTurn`; the name opens the rename menu |
| Track Bar | Track: Microphone, Call Audio | `TrackBar`: icon, label, one thin bar on a dB scale, red near clipping |

### Screens on the Redesign page

Main Window (Dark, Light), Recording (Dark), Menu Bar panels (Idle and Recording, Dark and Light,
on a colored backdrop so the glass reads), Event Detail (Dark, Light).

## Onboarding

Shown once, as a sheet on the main window (`WelcomeView`, first launch only). Five steps, each
skippable, following [DESIGN-PRINCIPLES.md](DESIGN-PRINCIPLES.md#onboarding-and-permissions): value
first, then each permission explained before macOS asks, and an email opt-in that is off by default.

| Step | Content | Primary |
|---|---|---|
| 1. Welcome | Record any call, Stays on your Mac, Ready for your schedule | Continue |
| 2. Allow Recording | Microphone and System Audio rows: Allow… → system prompt → Allowed, or Open Settings if denied | Continue |
| 3. Get the Speech Model | Download → progress and percent → Ready | Continue (the download goes on) |
| 4. See Your Meetings | Google Calendar (when the build has a Google client) and macOS Calendar: Connect… → Connected | Continue |
| 5. Can I Ask How It Goes? | "Yes, you may email me" switch (off), email field enabled only when on, Privacy Policy link | Start Using Undertone |

Step 5 appears only when the build has a Firebase project (`FeedbackSignup.isAvailable`); the
address goes to Firestore (`FeedbackSignup`), and the button stays disabled until a switched-on
address looks valid. Permission rows recheck their state when the app becomes active again, so
coming back from System Settings shows the change.

Layout: 560 pt sheet, 40 pt side padding; a 56 pt icon tile, Display title and Title 3 subtitle,
centered; content in a `bg/card` card with rows divided by separators; footnote in subheadline
secondary; footer with Back (bordered, hidden on step 1), step dots centered, primary button
(prominent). Steps cross-fade (ease-out 0.2 s).

| Figma | Variants / properties | SwiftUI |
|---|---|---|
| Icon Tile | Icon (instance swap); fill overridden per use | 28 pt (56 pt hero) rounded square, `color.gradient`, white symbol |
| Onboarding Row | State: Action, Done, Problem · Title, Text; nested Icon Tile | `WelcomeView.row`: trailing button, green "Allowed/Ready/Connected", or Open Settings link |
| Step Dots | Step: 1–5 | Dots in the footer; current one `label/primary`, others `label/quaternary` |

## Making a UI change

1. **Find the pieces.** Look up the tokens and components above. Reuse before inventing.
2. **Design in Figma first** for anything new or visibly different: change or add the component,
   bind every color, spacing and radius to a token, cover Light and Dark and every state.
3. **Update this file** in the same change: new tokens, new components, changed variants.
4. **Implement in SwiftUI** with the listed equivalents. Prefer system styles over custom drawing.
5. **Check the result** in both appearances and with the window focused and unfocused.

## Known gaps

- Sidebar, toolbar and window backgrounds are translucent materials in the app; Figma shows flat
  approximations. On the Redesign page, `material/glass` with the Glass/Regular effect only
  approximates Liquid Glass; the real look comes from the system in code.
- `waveform.badge.ellipsis` (menu bar icon while transcribing) cannot be drawn in Figma.
- The Redesign page shows a Now section at the top of the sidebar while recording; the app keeps
  the recording in its date group with the red dot.
- Apple's Search Field from the macOS 26 library does not follow our Color mode, so the file uses its
  own Search Field component.
