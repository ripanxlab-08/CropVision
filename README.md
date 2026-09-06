# Mobile-Based Crop Disease Detection with Image Verification and Stage-Based Treatment Recommendation

## Project Structure

```
project/
├── mobile_app/          # Flutter application
│   ├── lib/
│   │   ├── screens/     # auth, capture, home, result, history, calendar, assistant
│   │   ├── services/    # SupabaseService, InferenceService
│   │   └── models/      # Diagnosis model
│   └── pubspec.yaml
├── model/               # Python + PyTorch pipeline
│   ├── image_verification.py     # Quality + Validity checks (Phase 2, step 8)
│   ├── severity_estimation.py    # G0-G3 severity via HSV segmentation (step 13)
│   ├── train_mobilevit.py        # MobileViT Small training (steps 9-12)
│   └── requirements.txt
├── backend/             # Supabase
│   ├── supabase_schema.sql
│   └── seed_treatment_guidelines.sql
├── .env.example
└── .gitignore
```

---

## Phase 1 — Environment Setup

### 1. Flutter setup

```bash
# Install Flutter SDK (if not already): https://docs.flutter.dev/get-started/install
flutter --version        # confirm install
cd mobile_app
flutter pub get          # installs all dependencies from pubspec.yaml
flutter doctor           # check for missing platform tooling (Android SDK, Xcode, etc.)
```

Run on a connected device/emulator:
```bash
flutter run
```

> **Before running:** open `lib/main.dart` and replace the placeholder
> `SUPABASE_URL` / `SUPABASE_ANON_KEY` defaults, OR pass them at runtime:
> ```bash
> flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co --dart-define=SUPABASE_ANON_KEY=xxx
> ```

### 2. Python + PyTorch setup

```bash
cd model
python3 -m venv venv
source venv/bin/activate        # Windows: venv\Scripts\activate
pip install -r requirements.txt --break-system-packages
```

Verify PyTorch sees your GPU (optional but faster training):
```bash
python3 -c "import torch; print(torch.cuda.is_available())"
```

### 3. Supabase setup

1. Create a free project at https://supabase.com
2. Go to **SQL Editor** → run these three files **in order**:
   1. `backend/supabase_schema.sql`
   2. `backend/seed_crops.sql`
   3. `backend/seed_treatment_guidelines.sql`
3. Go to **Project Settings → API** → copy your `Project URL` and `anon public` key into `.env` (copy `.env.example` → `.env` first)
4. Go to **Authentication → Providers** → ensure Email/Password is enabled (this is the "custom User ID/password" auth from the spec — Supabase's email auth backs it; you can treat the email field as the farmer's User ID)

### 4. Flutter ↔ Supabase connection check

After steps 1-3, run the app and try signing up a test account from the
Signup screen. Confirm in the Supabase dashboard (**Table Editor → profiles**)
that a row was created — this confirms the full chain (Flutter → Supabase
Auth → Postgres RLS-protected insert) is working before moving to Phase 2.

---

## Phase 2 — Dataset & AI (in progress)

### Step 7 — Supported crops/diseases

`model/supported_crops.py` is the single source of truth for which
crop/disease classes the app supports (25 classes across Apple, Corn,
Grape, Potato, Tomato from PlantVillage). Run it directly to see the
full list: `python supported_crops.py`. Expand/trim this before
training — it must match your dataset folder names exactly.

### Step 8 — Image Verification (tested)

`model/image_verification.py` was tested against 5 synthetic images in
`model/test_images/` (healthy, diseased, blurry, dark, non-plant) and
correctly rejects each bad case with the right reason:

| Test image | Result |
|---|---|
| healthy_leaf.jpg | ✅ Valid |
| diseased_leaf.jpg | ✅ Valid (disease detection is a separate later stage) |
| blurry_leaf.jpg | ❌ "too blurry" |
| dark_leaf.jpg | ❌ "too dark" |
| non_plant.jpg | ❌ "no crop leaf detected" |

**Bug fixed during testing:** brightness is now checked *before* blur.
A very dark image naturally has low contrast, which depresses the
blur (Laplacian variance) score too — without the reorder, dark images
were misreported as "too blurry" instead of "too dark."

Run it yourself: `python image_verification.py test_images/dark_leaf.jpg`

### Step 13 — Severity Estimation (tested)

`model/severity_estimation.py` was tested against synthetic leaves with
known diseased-area percentages and correctly produced all 4 stages:

| Test image | Diseased area | Stage |
|---|---|---|
| healthy_leaf.jpg | 0% | G0 Healthy |
| mild_leaf.jpg | 3.9% | G1 Mild |
| diseased_leaf.jpg | 24.8% | G2 Moderate |
| critical_leaf.jpg | 44.2% | G3 Critical |

**Bug fixed during testing:** the original leaf-area mask only
recognized green-hued pixels as "leaf." Diseased/necrotic blotches are
often brown/reddish and fell *outside* that range — meaning diseased
pixels were excluded from the denominator entirely, silently deflating
severity (a ~25%-diseased test leaf was measuring as ~3%). Fixed by
making the leaf mask the union of healthy-tissue AND diseased-tissue
color ranges, since both are physically part of the same leaf.

Run it yourself: `python severity_estimation.py test_images/critical_leaf.jpg`

> **Before trusting these on real photos:** the synthetic tests prove
> the *logic* is sound, but `SEVERITY_THRESHOLDS` and the HSV ranges
> in both scripts were tuned against synthetic circles, not real
> lesions. Re-validate against ~20-30 real photographed leaves per
> crop once you have the dataset, and adjust thresholds if needed.

## Phase 3 — Treatment Recommendation (done + tested)

### Steps 14-16 — Disease → Severity → Treatment/Prevention mapping

`model/treatment_recommendations.py` is the single source of truth:
a `TREATMENT_MAP` dict keyed by the exact class names from
`supported_crops.py`, each mapped to G1/G2/G3 recommendation +
prevention text (G0/healthy classes only need a G0 entry - a model
should never call something healthy AND assign it a disease severity).

Currently filled in for Tomato (full 10 classes) and Potato (full 3
classes) plus representative Apple/Corn/Grape entries — 65 total
disease/severity combinations. Anything not yet filled in falls back
to a generic "consult local extension officer" message rather than
crashing, so you can expand coverage incrementally.

`backend/seed_treatment_guidelines.sql` is now **auto-generated** from
this Python file (regenerate it with the one-off script in the repo
history whenever `treatment_recommendations.py` changes) so the
Flutter app's database and the Python pipeline never drift out of
sync with each other.

### Step 17 — Connected to AI prediction (tested end-to-end)

`model/pipeline.py` chains everything into one function matching the
project's Final System Flow diagram exactly:

```
Image → Image Verification → [reject if invalid]
      → Disease Classification → Severity Estimation
      → Treatment Recommendation → result
```

The disease classifier is currently **mocked** (`classify_disease_MOCK`)
since MobileViT hasn't been trained yet — it returns a fixed label so
the rest of the pipeline (severity, treatment lookup, context match)
can be fully exercised now. Once training is done, only that one
function needs replacing with real inference; nothing else in the
pipeline changes.

Tested cases (`python pipeline.py <image> [expected_crop]`):

| Input | Result |
|---|---|
| `diseased_leaf.jpg` | Full result: Tomato Early Blight, G2 Moderate, correct treatment |
| `critical_leaf.jpg` + expected crop `Tomato` | Full result + `context_match: true` |
| `critical_leaf.jpg` + expected crop `Potato` | Full result + `context_match: false` with mismatch note (doesn't crash, just flags it) |
| `blurry_leaf.jpg` | Stops at `image_verification` stage, as designed |

Run it yourself: `python pipeline.py test_images/diseased_leaf.jpg`

## Phase 4 — Flutter Application (in progress)

### Steps 20-26 — Capture, verification, prediction, severity, treatment (wired, untested)

The Flutter app's image-processing logic is now a **Dart port** of the
tested Python pipeline, not hardcoded demo data:

- `lib/services/image_verification_service.dart` — ports
  `image_verification.py`'s quality/validity checks (blur via manual
  Laplacian convolution, brightness, plant-pixel HSV ratio).
- `lib/services/severity_estimation_service.dart` — ports
  `severity_estimation.py`'s HSV-based G0-G3 grading, including the
  "diseased pixels must count as leaf area too" fix.
- `lib/data/treatment_recommendations.dart` — **auto-generated** from
  `treatment_recommendations.py` (same script pattern as the SQL seed
  file), so all three copies (Python, SQL, Dart) stay in sync.
- `lib/screens/capture/capture_screen.dart` — now actually runs
  Verify → Upload → Classify (mocked) → Severity → Treatment in
  sequence, with live status text, instead of returning one hardcoded
  result regardless of the photo.

**Important - this has NOT been compiled or run.** This sandbox has no
Flutter/Dart SDK and can't reach pub.dev, so none of the Dart code
above has been type-checked. What *has* been verified: the underlying
math. I reimplemented each Dart algorithm in Python (same RGB→HSV
conversion, same hue/saturation/value thresholds) and ran it against
the same synthetic test images used for the Python version — results
matched within rounding (e.g. `diseased_leaf.jpg`: 24.76% in Python's
OpenCV pipeline vs 24.75% in the Dart-logic simulation). That confirms
the *logic* is a correct port, but Dart syntax errors, `image` package
API mismatches, or null-safety issues are still possible and untested.

**Before relying on this, you must run on your machine:**
```bash
cd mobile_app
flutter pub get
flutter analyze          # catches syntax/type errors
flutter run               # actually exercise it on a device/emulator
```
Fix whatever `flutter analyze` flags before testing on a real device.

### Steps 18-19, 27-30 — Auth, home, history, calendar, reminders, AI assistant

Already scaffolded from Phase 1 (see file list at the top of this
README) and unchanged in this round.

## Phase 5 — Supabase (audited + tested against real Postgres)

This sandbox has a real Postgres 16 server available, so rather than
just eyeballing the SQL, I stood up a throwaway database with minimal
`auth`/`storage` schema stubs (mimicking what Supabase provides) and
ran the actual schema + seed files against it.

**Two real bugs found and fixed:**

1. **`crops` and `treatment_guidelines` never had RLS enabled.** Every
   other table had `alter table ... enable row level security`, these
   two didn't. Practically: with just the public anon key, anyone
   could have inserted, updated, or deleted rows in these tables, not
   only read them. Fixed by enabling RLS with a read-only policy for
   authenticated users on both.
2. **The `crops` table was never seeded.** `diagnoses.crop_id`
   references it via foreign key, but nothing ever populated it -
   the reference table existed with zero rows. Added
   `backend/seed_crops.sql`, auto-generated from `supported_crops.py`
   (same pattern as the treatment guidelines seed) so it can't drift
   out of sync with what the model actually supports.

**Also added:**
- Storage delete policy (users can delete their own uploaded leaf
  images - previously only insert/select existed, so removing a
  diagnosis record would have left an orphaned file in storage)
- Indexes on `(user_id, created_at)` / `(user_id, reminder_date)` for
  diagnoses, reminders, and chat_messages - matching the actual query
  patterns in `SupabaseService` (always filtered by user, always
  ordered by a timestamp)

**Verified against real Postgres** (not just read - actually executed):
```
psql: CREATE TABLE, ALTER TABLE, CREATE POLICY x14, CREATE INDEX x3 → all succeeded
seed_crops.sql: INSERT 0 5  (5 crops)
seed_treatment_guidelines.sql: INSERT 0 65  (65 disease/severity entries)
relrowsecurity check: crops=t, treatment_guidelines=t, diagnoses=t,
                       profiles=t, reminders=t, chat_messages=t
```

All 6 tables now correctly enforce row-level security, and the run
order in the setup steps above (schema → seed_crops → seed_treatment_guidelines)
has been updated to match what actually works (seed_crops must run
before seed_treatment_guidelines only because of read-order in this
doc, not a hard dependency - but schema must run first for both).

## Phase 6 — Integration & Testing

### Steps 38-41 — Automated test suite (52 tests, all passing)

`model/tests/` is a real pytest suite, not ad-hoc manual script runs:

```bash
cd model
pip install pytest --break-system-packages
python -m pytest tests/ -v
```

| File | Covers |
|---|---|
| `test_image_verification.py` | Step 38: valid/invalid images (blurry, dark, overexposed, non-plant, low-res, missing file) |
| `test_severity_estimation.py` | Step 40: G0-G3 thresholds, monotonicity, pixel-count bounds |
| `test_treatment_recommendations.py` | Step 41: known combos, fallback behavior, healthy/severity contradiction, cross-file name consistency |
| `test_pipeline_integration.py` | Full pipeline: rejection stops early, valid images complete, context-match logic |

**A second real bug found by this suite:** a cross-check test
(`test_all_treatment_map_keys_match_supported_crops`) caught that
`Corn___Cercospora_leaf_spot Gray_leaf_spot` in `supported_crops.py`
(matching the actual PlantVillage folder name, which really does mix
underscores and spaces) didn't match
`Corn___Cercospora leaf spot Gray leaf spot` in
`treatment_recommendations.py` (missing underscores). Without this
test, a correctly-classified Corn Cercospora leaf would have silently
fallen back to generic advice instead of its specific treatment -
exactly the kind of bug that's invisible in manual testing because you
have to think to test that specific class. Fixed the source file and
regenerated the SQL seed + Dart file from it; re-verified against a
fresh Postgres instance.

**Final result: 53 tests, 0 failures.**

### Steps 37, 42, 43 — Cannot be done in this sandbox

Being direct about the boundary here rather than pretending otherwise:

- **Step 37 (connect trained model)** needs a real MobileViT checkpoint,
  which needs the dataset, which needs internet access this sandbox
  doesn't have. Still mocked in both `pipeline.py` and `capture_screen.dart`.
- **Step 42 (test database and authentication) - the live-Supabase half**
  is done (schema + RLS verified against real Postgres above). The
  Flutter-app-talking-to-a-real-Supabase-project half needs your actual
  project credentials and can't be tested from here.
- **Step 43 (mobile testing)** needs a physical device/emulator and the
  Flutter SDK, neither available in this sandbox.

**What you need to do next, in order:**
1. `cd mobile_app && flutter pub get && flutter analyze` - fix any errors
2. Create the Supabase project, run the 3 SQL files, add credentials
3. `flutter run` on a device/emulator, sign up, run through the capture flow with a real photo, confirm the mocked "Tomato Early Blight" result appears with treatment + prevention text
4. Once dataset + training (Phase 2) are done on your machine, swap the mock classifier for real inference in both `pipeline.py` and `capture_screen.dart`

## Manual Dart review (in lieu of `flutter analyze`, which this sandbox can't run)

No Flutter/Dart SDK exists here and pub.dev isn't reachable, so nothing
below was compiler-verified. But I went through every `.dart` file by
hand and checked what's mechanically checkable without a compiler:

- **Brace/paren/bracket balance** across all 17 files - all balanced.
- **Every relative import** resolves to a real file - zero broken imports.
- **Every routed screen class** (`main.dart`'s `routes:` map) exists
  with a matching name and a `const Constructor({super.key})`.
- **Every `SupabaseService` method call** from a screen matches that
  method's actual name, parameter names, and required/optional status
  - checked `signIn`, `signUp`, `addReminder`, and all others field by
  field.
- **Every field access** on `Diagnosis`, `SeverityResult`,
  `VerificationResult`, and `TreatmentEntry` matches what those
  classes actually define.
- **`pubspec.yaml`** is valid YAML.

**Three real risks found and removed** rather than left for you to
discover at build time:

1. `inference_service.dart` used the `pytorch_lite` package with an
   API I wrote from memory, unverifiable without pub.dev access. It
   was also dead code (nothing calls it - `capture_screen.dart` uses
   the mock classifier instead). Replaced with a documented stub that
   throws `UnimplementedError`, and removed `pytorch_lite` from
   `pubspec.yaml` entirely. Decide on a real package (pytorch_lite,
   tflite, onnxruntime, etc.) once you actually have a trained model
   to export and can check that package's current docs.
2. `pubspec.yaml` referenced `assets/models/mobilevit_mobile.pt`,
   `assets/models/labels.txt`, and `assets/images/` - **none of which
   exist in this scaffold.** Flutter fails the entire build if a
   declared asset path doesn't exist. Removed the `assets:` block;
   add it back once those files are real.
3. `camera` and `flutter_local_notifications` were declared but never
   imported anywhere, and both need native platform setup (permissions,
   notification channels) that hasn't been done. Removed both to cut
   build-risk with no functional loss - `image_picker` already handles
   camera capture, and reminders currently just live in the Supabase
   table without push notifications.

**What this review can't catch:** actual Dart type-checking, null-safety
violations, or whether `supabase_flutter`/`table_calendar`/`image`'s
real APIs match what I wrote (I'm most confident about `image` v4.x
since that API surface is one I have solid grounding in; least
confident about anything I can't cross-reference). `flutter analyze`
is still the real verification step - this pass just removes the
failure modes I could find without it.

### Step 6 — Getting the real dataset (run on your own machine)

This sandbox can't reach Kaggle/Hugging Face directly, so download
PlantVillage locally:

```bash
pip install datasets --break-system-packages
python3 -c "
from datasets import load_dataset
ds = load_dataset('mohanty/PlantVillage', 'color')
ds['train'].save_to_disk('./plantvillage_raw')
"
```

Then reorganize into the `ImageFolder`-style structure
`train_mobilevit.py` expects (one subfolder per class, matching
`supported_crops.all_class_names()`):

```python
import os
from datasets import load_from_disk

ds = load_from_disk('./plantvillage_raw')
label_names = ds.features['labels'].names

for i, example in enumerate(ds):
    label = label_names[example['labels']]
    out_dir = f"./dataset/{label}"
    os.makedirs(out_dir, exist_ok=True)
    example['image'].save(f"{out_dir}/{i}.jpg")
```

### Steps 9-12 — Training (run on your own machine with a GPU)

Once `./dataset/` is populated:

```bash
cd model
python train_mobilevit.py --data_dir ./dataset --epochs 15
```

Start with 2-3 epochs first to confirm the pipeline runs end-to-end
(no path/shape errors) before committing to a full run. `timm`
downloads ImageNet-pretrained MobileViT-Small weights automatically on
first run (needs internet access once, for that download only).

---

## Known placeholders to replace as you progress

| File | Placeholder | Replace with |
|---|---|---|
| `mobile_app/lib/main.dart` | `YOUR_PROJECT` / `YOUR_ANON_KEY` | Real Supabase credentials |
| `mobile_app/lib/services/inference_service.dart` | Hardcoded `38` classes, dummy return | Real class count + parsed prediction after training |
| `mobile_app/lib/screens/capture/capture_screen.dart` | Hardcoded demo diagnosis | Real call to `InferenceService` + severity pipeline |
| `mobile_app/lib/screens/assistant_screen.dart` | Placeholder reply | Supabase Edge Function calling an LLM API |
| `model/severity_estimation.py` | `SEVERITY_THRESHOLDS` | Tune against ~50-100 hand-checked images per crop |

---

## Next steps (once Phase 1 is confirmed working)

1. Download PlantVillage dataset, confirm folder structure matches `train_mobilevit.py` expectations
2. Run a short training pass (2-3 epochs) to confirm the pipeline runs end-to-end before a full 15+ epoch run
3. Export trained model to TorchScript (`torch.jit.script(model).save(...)`) and drop into `mobile_app/assets/models/`
4. Wire `InferenceService.classify()` to the real model output
