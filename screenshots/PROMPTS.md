# Polish prompts — paste scaffold + prompt into Gemini (Nano Banana) / any image editor AI

Workflow:
1. Polish `01-run-your-gym/scaffold.png` first with Prompt 1.
2. For screenshots 2–5, attach TWO images: that screenshot's scaffold + your approved result from step 1 (style reference). Use Prompt 2–5.
3. Resize every result back to exactly 1290×2796 before upload (command at bottom).

---

## Prompt 1 — RUN (01-run-your-gym/scaffold.png)

This is a SCAFFOLD for an App Store screenshot — a rough layout showing the correct text, device frame position, and app screenshot placement. Transform it into a polished, professional App Store marketing screenshot.

KEEP EXACTLY AS-IS: the headline text (wording, position, size), the app screenshot shown on the phone screen, the background colour (#2C6E7A teal).

ENHANCE:
- Replace the placeholder device frame with a photorealistic iPhone 15 Pro mockup — accurate proportions, subtle reflections and shadows, same position and size as the scaffold. The bottom of the phone bleeds off the bottom edge.
- PRIMARY BREAKOUT: the white rounded quick-actions card from the app screen (four buttons: "Add member", "Collect", "Enquiry", "Scan QR") pops out of the phone — scaled up much larger, extending beyond both left and right edges of the device frame, same vertical position as on screen, not rotated, floating with a soft drop shadow.
- Background stays flat solid teal — no glows, gradients, or patterns.
- Text crisp, bold, highly readable. No watermarks, no extra text, no invented UI.

## Prompt 2 — TRACK (02-track-members/scaffold.png) — attach style reference too

You are creating the next screenshot in an App Store screenshot SET.
- FIRST image: the SCAFFOLD — defines layout: headline wording/position, device placement, app screen contents.
- SECOND image: the STYLE TEMPLATE (approved screenshot 1) — match its device frame rendering EXACTLY, same text treatment, same flat teal background, same polish.

PRIMARY BREAKOUT: one member row card from the list (e.g. "shashank singh · monthly pro · exp 11 Aug 2026" with its green "Active" badge) pops out — scaled up much larger, extending beyond both edges of the device frame, same vertical position, not rotated, soft drop shadow. Same colours/content as on screen, invent nothing.
No watermarks, no extra text.

## Prompt 3 — SCAN (03-scan-checkins/scaffold.png) — attach style reference too

Same set-consistency instructions as Prompt 2 (scaffold = layout, style template = look).

PRIMARY BREAKOUT: the "In today" check-in feed card (rows: ishan singh, shashank singh with In/Out times) pops out — scaled up, beyond both device edges, same vertical position, soft drop shadow. Content exactly as on screen.
No watermarks, no extra text.

## Prompt 4 — COLLECT (04-collect-payments/scaffold.png) — attach style reference too

Same set-consistency instructions as Prompt 2.

PRIMARY BREAKOUT: the dark green "Collected this month ₹15,998 ↑300% vs last month" hero card pops out — scaled up, beyond both device edges, same vertical position, soft drop shadow. Content exactly as on screen.
No watermarks, no extra text.

## Prompt 5 — SEE (05-see-revenue/scaffold.png) — attach style reference too

Same set-consistency instructions as Prompt 2.

PRIMARY BREAKOUT: the dark revenue chart card ("Collected · Jul ₹22.0k ↑83%" with the green line chart) pops out — scaled up, beyond both device edges, same vertical position, soft drop shadow. Content exactly as on screen.
No watermarks, no extra text.

---

## Resize results to App Store dimensions (required)

Generated images rarely come back exactly 1290×2796. Put results in `screenshots/final/` named `01.png` … `05.png`, then:

```bash
cd /Users/wiredtechie/Desktop/gym_crm_android/screenshots/final
for f in *.png *.jpg; do
  W=$(sips -g pixelWidth "$f" | tail -1 | awk '{print $2}')
  H=$(sips -g pixelHeight "$f" | tail -1 | awk '{print $2}')
  CROP_W=$(python3 -c "print(round($H * 1290 / 2796))")
  sips --cropOffset 0 $(python3 -c "print(round(($W - $CROP_W)/2))") --cropToHeightWidth $H $CROP_W "$f"
  sips -z 2796 1290 "$f"
done
```

Or just tell Claude "resize the finals" — I'll do it.
