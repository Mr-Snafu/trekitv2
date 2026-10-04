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
| Feed | Private, newest-first activity from accessible adventures | Initial live version shows adventure creation and journal-entry activity |
| Adventures | Organize owned and shared trips and open their journals | Live with lifecycle groups, cover images, search, filters, sorting, editing, deletion, sharing, entries, and photos |
| Create | Start an adventure or add a journal entry from anywhere | Initial creation menu is live |
| Circle | Manage trusted connections, requests, blocking, and TrekIt IDs | Navigation destination is live; full relationship model is pending |
| Profile | Identity, verification, settings, privacy, export, and account controls | Initial account, verification, password, deletion, and sign-out controls are live |

## Planned product capabilities

### Feed

- Show only activity from authorized adventures.
- Support adventure, journal-entry, photo, sharing, and future comment activity.
- Add quick snippets and a clear pending state for offline submissions.
- Use friendly dates and useful summaries rather than raw timestamps.

### Adventures

- Draft, Live, and Completed lifecycle states are live.
- Adventure cover images and grouped image-card layouts are live.
- Preserve private membership roles and owner controls.
- Keep journal memories ordered by their memory date and prohibit future entry dates.

### Create

- Offer context-aware creation for adventures, journal entries, photos, and quick snippets.
- Allow a user to choose the destination adventure without navigating away first.
- Preserve unsent work when connectivity is interrupted.

### Circle

- Give each user a shareable TrekIt ID.
- Support incoming and outgoing connection requests.
- Support remove, decline, block, and unblock actions.
- Keep Circle relationships separate from access to a specific adventure.

### Profile

- Support display identity and profile details.
- Centralize account, notification, privacy, sharing, help, and legal settings.
- Add personal data export before broad release.
- Retain secure account deletion and reauthentication behavior.

## Development sequence

1. Establish Feed-first navigation and a real private activity timeline.
2. Add adventure lifecycle states and cover images.
3. Add Quick Snippets and offline delivery states.
4. Build the Circle relationship and invitation model.
5. Expand Profile, notifications, privacy controls, and data export.
6. Add comments and richer feed events.

Every phase should be checked against this blueprint, tested at mobile width, deployed through a preview, verified against the live build, and backed up to GitHub.
