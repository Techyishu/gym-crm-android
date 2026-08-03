# GymCRM Home Screen Widgets — Design Brief (Gym Owner / Staff)

Paste the block below into Claude / Stitch / any design tool.

---

I need home screen widget designs for my mobile app. I'm not going to tell you which
widgets to make or how they should look — read the product below, decide what deserves
a spot on the user's home screen, and design it. Give me **at least 5–6 distinct widget
designs**, and tell me briefly why each one earned its place.

## What the app is

**GymCRM** — gym management software for small and mid-size independent gyms, mostly
in India. The widgets are for **one audience only: the people who run the gym** —
the owner, and below them a manager, trainer, or front-desk staff. Permissions differ
by role; a trainer sees far less than an owner. Design for the owner as the primary
user.

(The app also has a separate self-service side for gym members, but that's out of
scope here. Ignore it.)

## What gym staff do in the app

- **Dashboard** — business health at a glance
- **Members** — the member roster, individual member profiles with photo, plan and
  history; bulk import from CSV
- **Check-in** — scanning members in at the door via QR code, and displaying a gym QR
  for members to scan themselves in
- **Billing** — invoices, payments collected, who owes money, upcoming payments due
- **Leads** — prospects who enquired but haven't joined yet, and following them up
- **Classes** — scheduling group classes and sessions
- **Communications** — messaging members, WhatsApp reminders
- **Workout & diet plans** — assigning training and nutrition plans to members
- **Reports** — revenue, attendance, retention over time
- **Staff** — managing employees and their access levels
- **Settings & automated reminders** — renewal nudges, dues follow-ups

## Context that matters

- The owner is not a desk person. They're on the gym floor, checking their phone
  between things — many short looks a day, rarely a long session.
- Membership expiry drives the whole business. Members forget to renew and the gym
  silently loses revenue. Renewals, dues and expiring memberships are the
  money-critical numbers.
- Leads go cold fast. A prospect who enquired yesterday and wasn't called is lost.
- The busiest physical moment is the door at peak hours — members arriving,
  someone scanning them in.
- Money is in Indian Rupees (₹).
- A gym often has more than one person with the app: owner at home, manager at the
  desk. Role changes what a widget is allowed to show.
- Widget data comes from a server and can be a few minutes stale.
- A home screen is a semi-public surface — anyone standing nearby can read it, and
  member data is confidential.

## What I want back

- 5–6 or more widget designs.
- Multiple sizes where a widget earns more than one (small square, medium rectangle,
  large — your call which deserve which).
- Light and dark mode for each.
- Android and iOS versions.
- Empty, loading/stale, and error states wherever a widget shows live data.
- At least one realistic home-screen mockup per platform showing widgets in context
  next to normal app icons.
- One line per widget on why it's worth a home screen slot — and if one of the
  obvious ideas is actually a bad widget, say that too.
