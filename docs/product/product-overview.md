# Legacy — Product Overview

**Source of truth:** https://legacy-preview-rho.vercel.app

Last synced: 2026-06-15

---

## One-liner

**Legacy** — The places remember you. Drop memories at locations. Return to unlock them. Let people walk through your life, block by block.

---

## Core promise

A memory isn't something you scroll past. It's something you arrive at.

- **Authenticity is architectural, not enforced.** Photos you already took (camera roll, GPS-tagged, months/years old) are connected to the exact place they were made. You can't reshoot your past.
- **Presence is the paywall.** You can't share a memory from your couch. You have to be there. This friction is the feature.
- **Density compounds.** A campus after 10 years of use is richer than one used for a month. Memories accumulate forever.
- **No feed. No algorithm. No viral mechanics.** The business model is features and infrastructure, not attention.

---

## The Five Drop Methods

Each serves a distinct use case and has different composition/privacy rules.

| V# | Name | Flow | Source | Default privacy | Seals available | Use case |
|---|---|---|---|---|---|---|
| V1 | **Pin** | 1-tap | camera/gallery | private | None (basic only) | "I'm here, I don't want to lose this." Frictionless, no menus. |
| V2 | **Treasure Chest** | Compose full | camera/gallery | (choice) | Full suite | "I'm hiding this for someone with specific conditions." |
| V3 | **Import** | Bulk from camera roll | EXIF GPS (on-device cluster) | private-only | None | "Seed my map on first launch." 50+ clusters pre-generated. |
| V4 | **Note in a Bottle** | Text + location + seal | keyboard input | (choice) | Time-only | "A message for someone, locked to time and place." |
| V5 | **Prompt** | Question + replies | keyboard input | friends/public (P3) | Conditions | "Ask people who return here what they think." Phase 3. |

**Key constraint:** V3 (Import) memories are **private-only**. To share a photo imported from camera roll, the owner must perform a live drop (V1 or V2) at that same location first.

---

## Core features (Phase 1)

### Memory Lane
- Grid of own memories, sorted by recency of drop (oldest first)
- Read-only; no deletion (memories are permanent)
- Shows teaser: photo, drop date, "time since dropped" delta
- Tap to unlock and see full memory (no proximity check for own memories)
- Option to "re-earn" by returning to the location and re-locking

### Wander Mode
- Full-screen map, basemap only (no pins initially visible)
- Walk around → foreground location polling
- Eligible memories surface as pins with **warmth cue** (non-directional ambient gradient)
- Tap pin → unlock if in proximity; if not, shows teaser + "walk closer"
- Post-unlock: see full memory + all media
- Own memories re-lock after viewing; return to earn them again

### Proximity unlock
- Distance from drop point determines unlock-ability
- **Asymmetric bubbles:**
  - Own: 25m base + up to 75m accuracy buffer
  - Others': 20m base + up to 25m accuracy buffer, AND rejected if accuracy > 50m
- **Dwell requirement:** Non-owned memories need two proximity checks ≥20s apart
- **Cooldown window:** Memory not discoverable until cooldown elapses (default 24h, configurable)

### Background detection
- Significant-change location service wakes the app on ~500m+ movement
- Region monitoring on ~14 nearest own pins + ~5 coarse zones with eligible others' content
- Push notification on entry to eligible pin's region (if proximity validates)
- Zero location hardware at steady state

### On-device import
- First launch: app reads camera roll for GPS-tagged photos
- On-device clustering: grid-snap to ~150m cells, merge adjacent, rank by density
- Presents ~50 clusters for user to select
- Bulk import: one cluster = one memory at centroid
- Raw GPS never leaves device; only cluster centroid transmitted

### Privacy controls
- **Private:** Owner only
- **Recipients:** Phone-number ACL (Phase 2)
- **Friends:** Mutual connection (Phase 2)
- **Public:** Anyone 16+ (Phase 3)

---

## Premium features (in-app purchases, Phase 1 onwards)

| Tier | Price | What unlocks |
|---|---|---|
| Free | — | Complete experience. Most users don't pay. |
| Premium seals | $0.99–$9.99 each | Age-based (open when X turns 18); atmospheric (sunset, winter, rainy); recurring (anniversary). |
| Legacy chains | $2.99 | Location sequences (send someone on a path through your memories). |
| Vault expansion | $99/year | Shared family map across generations; child access at age 13; seal messages for milestones. |
| Institutional | Custom/year | Universities, festivals, tourism boards. Infrastructure, not attention. |

---

## Phase 2 features (Social)

### Recipients
- Owner specifies phone numbers at drop time
- Recipient must sign up with that phone number and pass proximity
- Summons: owner sends SMS to recipient "I left something for you here [link]"
- Deep link brings recipient to map with memory surfaced

### Friends graph
- Mutual connections; accept = friend-tier memories become discoverable
- Friends get proximity-based discovery like recipients do

### Responses/Replies
- A reply is a full Memory attached to another memory's pin
- Submitted by discoverer at the same location
- Original owner discovers reply only on next return
- Place-locked by design (can't reply from couch)

### Vault
- Shared memory map across family members
- Passed down across generations
- Child access unlocks at 13
- Sealed messages for milestones (16th birthday, graduation, wedding day)
- Premium pricing: ~$99/year; near-zero churn (leaving means abandoning irreplaceable content)

### Seals & Conditions (premium, full suite)
- **Seals (time gates):** fixed date, duration, age-based, recurring
- **Conditions (state gates):** time of day, season, weather, co-presence, long absence, nth return
- **Mandatory fallback:** no user can be stranded; all conditions have a `condition_time_fallback` timestamp

---

## Phase 3 features (Network effects)

### Public memories
- Any user 16+
- Content-screened before becoming discoverable
- Public drops near sensitive locations (homes, schools) receive extra scrutiny
- Reportable content auto-hides pending review

### Institutional layer
- Universities: alumni memories across graduating classes; current students discover decade of presence
- Festivals: attendees drop memories during event; venue lights up on return next year
- Tourism boards: iconic locations accumulate human history
- Museums: staff-curated memory trails unlocked as visitors move through space
- Corporate campuses: legacy layers for alumni cultures

Implementation: curated layer license (annual, per geography); no ads inside the experience ever.

### Creator trails
- Guided paths through a series of memories
- Enable self-guided walking tours of curated history

### Android

---

## Positioning vs. competitors

| Competitor | What they do | Why Legacy is different |
|---|---|---|
| Instagram / TikTok | Feed-based social; you perform for an audience | Legacy has no feed, no followers, no algorithm. Memories compound, never buried. |
| Google Photos / iCloud | Photo library organized by date/face | Legacy is opposite: organized by *place* and requires you to *go there* to see it. |
| Snapchat Snap Map | Live map of where friends are *now* | Legacy is about *then*. Snaps disappear; memories compound forever. |
| BeReal | Real-time authenticity enforcement | Legacy uses photos you already took (months/years old, for no audience). Authenticity is architectural. |
| FindMy / Life360 | Location tracking for families | Legacy never tracks. Only stores where you *were* (one moment, one drop). |
| Geocaching | Public game, hunt for containers | Legacy is personal and quiet. Geocaching is public; Legacy is secret until you're there. |
| Day One / journaling | Diary with location tags | Day One: timestamp. Legacy: place does the work. Standing where it happened is different from reading about it. |

---

## Monetization

### Free tier
- Drop unlimited memories (storage bounded: ~500MB/yr generous tier)
- Camera roll seeding on day one
- Basic seals (fixed date, duration)
- Background proximity detection (own memories)
- Friends, discovery, replies

### Premium (transactional, $0.99–$9.99)
- Age-based seals
- Atmospheric conditions (sunset, winter, rainy)
- Co-presence locks (3 people required)
- Recurring seals (yearly)
- Legacy chains (location sequences)
- Expanded recipient lists (up to 20)

### Vault ($99/year)
- Shared family memory map
- Passed down across generations
- Child access at 13
- Sealed messages for milestones
- Premium responses (keep/vault choice on unlock)

### Institutional (custom/year)
- Curated legacy layer at geography (university, festival, tourism board)
- Alumni memories across graduating classes
- Anonymized engagement data (returns, density)
- No ads inside experience, ever

**Philosophy:** Storage is generous (all memories improve the product). We charge for emotional infrastructure (seals, conditions, sharing, vault) and institutional curation. No ads. No feed. No follower counts.

---

## Use cases (real-world examples)

### Campus time machine (annual recurrence)
- Drop memories across 4 years on a handful of blocks
- Graduate, go to homecoming 5 years later
- Walk the same paths; 21-year-old self shows up around you
- Every graduating class adds density; the place gets richer

### Travel memory layer
- Road trip with friends, drop memories at pit stops, weird motels, landmarks
- Return to same route next year or in 10 years
- Map accumulates the history of the journey

### Family legacy
- Grandparent drops memories at childhood home
- Parent adds memories from growing up there
- Grandchild explores three generations of presence in one place

### Festival/concert return
- Attend festival, drop memories at specific stages, moments
- Return next year; old memories surface as you walk the grounds
- Year-over-year density builds anticipation

### Proposal sites & meaningful places
- Couple's anniversary: return to proposal bench; memory unlocks
- Home: drop memories marking different chapters (proposal, baby's first day home, etc.)
- Revisit becomes a ritual

---

## Privacy posture

- **No movement log:** Location submitted to API, validated, discarded. Not logged, not persisted.
- **Coordinates never sent to clients:** Only owner sees drop point. Others see teaser + media URLs, no coordinates.
- **Imported GPS on-device:** EXIF GPS stripped on-device before any upload. Raw coordinates never hit servers.
- **Background detection coarse:** Device receives geohash cells for eligible others' memories, never exact points.
- **Media signed URLs only:** Storage bucket is private. No raw keys to clients. URLs expire after minutes.
- **EXIF stripped twice:** Client (privacy) + server (guarantee).
- **CSAM day-one:** Hash-matching on every upload. Mandatory reporting on match.
- **No ads. Ever.** Across free, premium, and institutional tiers.

---

## Brand voice & positioning

**What Legacy is:**
- A pilgrimage to yourself.
- For people who see the world as a map of their own history.
- A way to leave a trail of yourself for people you care about.
- A proof that the places remember you.

**What Legacy is not:**
- A social network (no feed, no viral mechanics)
- A tracking app (no movement history, ever)
- A competitor to Instagram (different purpose, different business model)
- A photo archive (photos are connected to *place*, not just time)

---

## Contact & resources

- **Website:** https://legacy-preview-rho.vercel.app
- **Getting early access:** https://legacy-preview-rho.vercel.app/#waitlist
- **Questions about the product:** josephamprey@gmail.com
