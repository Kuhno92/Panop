# 0012. One look: tokens, cards, pills, and what must not be done to a list

**Status:** accepted. Checked on iPhone and Apple TV, and (screens only) on iPad; **not looked at on a Mac**.

## Context

The owner asked for a modern look with "a wow effect" that stays light and instant. The app had a dark blue page with two
glows, and screens that had grown their own styles: system buttons, grey rows, different corners.

## Decision

`Panop/Views/Design/Theme.swift` holds what the screens share, and nothing in it costs anything to scroll over:

- **One accent**, a blue leaning to violet (`Theme.blue`, `Theme.violet`, `Theme.accent`). Not `Color.accentColor`, which
  is white on Apple TV.
- **`glassCard`**: a faint fill and a hairline that is lighter at its top edge. For rows and cards that repeat. No blur
  and no shadow, since either, repeated down a list, is an offscreen pass per row.
- **`PillButtonStyle` / `pageButton`**: the accent gradient for the main choice, glass for the others. Apple TV keeps the
  system's styles, which carry the focus effect.
- **`PosterFocusStyle`** (Apple TV only): the focused poster rises, brightens a touch and glows. One scale and one shadow
  on the one card in focus.
- **`AmbientColor`**: a poster averaged to one pixel, lifted to a colour that shows on a dark page, for the glow behind
  a hero.
- A hero on a phone is the poster itself, full width, with a dark band behind the words; on a wider screen the words are
  on the left and the poster on the right with a glow, and the carousel's arrows have room at the sides.

## Learned the hard way

- **A bar that is too full breaks its taps.** Six icons, a badge and a larger play button did not fit a phone's width;
  the badge was squeezed into a column of letters and a tap on TV Guide fell through to the picture. The bar's icons now
  answer over 44 points each (`barTarget`), the spacing on a phone is 8, and the badge is `fixedSize`. Check a bar's
  width before adding to it.
- **A list's rows are black unless told otherwise.** `listRowBackground(.clear)` on each row or section, or the page
  gradient does not show.
- **`.focusSection()`** is for tvOS only (it is unavailable on iOS), and a wide control above a narrow one sends Down to
  the nearest thing below its middle: TV Guide is reached with Left from Sort.
- **A `Label` in a list row shows its icon alone** unless the button's style says `labelStyle(.titleAndIcon)`.

## Not done

The Mac window (no way to capture it from here), Apple TV focus effects other than the posters, and a Settings
restyle: it was already grouped, with icons, and was left alone.
