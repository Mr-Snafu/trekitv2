# TrekIt V2 Product Blueprint

This document is the source of truth for TrekIt V2 development. TrekIt is a private adventure journal for trusted friends and family. The supplied mobile prototypes guide the layout and navigation, but they do not define finished functionality by themselves.

## Product principles

- Private by default. There is no public discovery feed, trending content, or public profile directory.
- A person sees activity only from adventures they are authorized to access.
- The signed-in landing page is Feed.
- Mobile navigation always centers the five primary areas: Feed, Adventures, Create, Circle, and Profile.
- Firebase rules must enforce access and validation even when the interface is bypassed.
- Existing user data must remain compatible as features evolve.

## Primary navigation

| Area | Purpose | Current status |
| --- | --- | --- |
| Feed | Private, newest-first activity from accessible adventures | Live with adventure, journal-entry, photo, comment, sharing, and Quick Snippet activity plus a local retry queue |
| Adventures | Organize owned and shared trips and open their journals | Live with lifecycle groups, cover images, search, filters, sorting, editing, deletion, sharing, entries, and photos |
| Create | Start an adventure or capture content from anywhere | Live with adventure, journal-entry, photo-first memory, and Quick Snippet flows |
| Circle | Manage trusted connections, requests, blocking, and TrekIt IDs | Live with private IDs, requests, cooldowns, remove, block, and unblock controls |
| Profile | Identity, verification, settings, privacy, export, and account controls | Live with editable identity, saved preferences, JSON export, help/legal summaries, and account controls |

## Planned product capabilities

### Feed

- Show only activity from authorized adventures.
- Support adventure, journal-entry, photo, sharing, and comment activity. *(Live)*
- Quick Snippets and a clear locally saved pending/retry state are live.
- Use friendly dates, grouped time periods, and useful event summaries rather than raw timestamps. *(Live)*

### Adventures

- Draft, Live, and Completed lifecycle states are live.
- Adventure cover images and grouped image-card layouts are live.
- Preserve private membership roles and owner controls.
- Keep journal memories ordered by their memory date and prohibit future entry dates.

### Create

- Offer context-aware creation for adventures, journal entries, photos, and quick snippets. *(Live)*
- Allow a user to choose the destination adventure without navigating away first. *(Live)*
- Preserve unsent adventure and journal text, dates, destination context, and Quick Snippets when connectivity is interrupted. Photos must be reselected after recovery for privacy and browser compatibility. *(Live)*

### Circle

- Each user receives a private, shareable TrekIt ID.
- Incoming and outgoing connection requests with decline cooldowns are live.
- Remove, decline, block, and unblock actions are live.
- Keep Circle relationships separate from access to a specific adventure.

### Profile

- Editable display identity and profile details are live.
- Account, notification, privacy, sharing, help, and legal controls are centralized in Profile.
- Personal JSON data export is live.
- Retain secure account deletion and reauthentication behavior.

## Development sequence

1. Establish Feed-first navigation and a real private activity timeline.
2. Add adventure lifecycle states and cover images.
3. Add Quick Snippets and offline delivery states. (Live)
4. Build the Circle relationship and invitation model. (Live)
5. Expand Profile, notifications, privacy controls, and data export. (Live)
6. Add comments and richer feed events. *(Live)*
7. Expand the central Create hub with destination-aware photo and Quick Snippet flows. *(Live)*
8. Polish Feed readability with friendly time labels, day grouping, and richer event context. *(Live)*
9. Add account-scoped local draft recovery for adventure and journal creation. *(Live)*

Every phase should be checked against this blueprint, tested at mobile width, deployed through a preview, verified against the live build, and backed up to GitHub.
