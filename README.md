# UniClub v2

UniClub is a Flutter campus community platform backed entirely by Supabase. The
previous Firebase/Cloudinary data path has been removed. Authentication,
Postgres data, row-level authorization, Realtime feeds, file storage, Edge
Functions and notification state share one Supabase security model.

## Implemented product

### Identity and profiles

- Email/password sign-up with mandatory email verification
- Forgot-password deep link and secure password change
- Google OAuth and Sign in with Apple
- Account suspension gate and privacy-preserving account deletion
- User blocking/following and a blocked-user management screen
- Editable name, username, avatar, bio, department, academic year, skills,
  and interests
- Public profiles, direct-message entry, badges, club-position history, and
  event/registration history

### Discovery, social, and communication

- Global search across clubs, events, users, colleges, announcements, and posts
- Type, category, college, date, and location filters
- Event and hackathon feeds
- Posts with images, likes, comments, mentions, and external sharing
- Instagram-style grouped 24-hour club stories and views
- Direct and club conversations using Supabase Realtime
- In-app notification center, read state, preferences, and push-dispatch queue

### Clubs

- Club discovery, follows, join requests, My Clubs, and club leaderboards
- Dashboard metrics for members, events, followers, and approvals
- Permission-based positions: President, Vice President, Secretary, Treasurer,
  Event Head, Technical Head, Marketing Head, Faculty Coordinator, Volunteer,
  Member, and custom positions
- Announcement feed with images/PDF attachments, polls, pinning, immediate
  publishing, and scheduling

### Events, registration, and attendance

- Event/hackathon/competition/workshop/meetup creation
- Start/end time, deadline, venue, capacity, waiting list,
  auto/manual approval, custom registration fields, ticket types, paid tickets,
  speakers, guests, sponsors, agenda, feedback schema, and certificate settings
- Registration approval/rejection/waitlist flow
- Provider-neutral checkout, payment webhook, invoice records, refunds schema,
  coupon schema, and private certificate storage
- QR check-in/check-out, manual attendance, late-arrival tracking, attendance
  analytics, and no-show counts

### Finance and platform

- Club budgets, receipt uploads, expense approvals, calculated totals, and CSV
  financial reports
- Interest-ready recommendation data model for events, clubs, people, and
  competitions
- Club leaderboard scoring, badges, light/dark/system themes, and a
  minimum-version gate

The canonical schema is
[`supabase/migrations/202607240001_uniclub_production_schema.sql`](supabase/migrations/202607240001_uniclub_production_schema.sql).
It includes constraints, indexes, triggers, storage buckets, Realtime
publications, and row-level security policies. Sensitive authorization is
enforced in Postgres rather than trusted to UI buttons.

## Local setup

Requirements: current stable Flutter, a Supabase project, Supabase CLI, Xcode
for iOS, and Android Studio/JDK 17 for Android.

1. Link and deploy the Supabase backend:

   ```sh
   supabase login
   supabase link --project-ref YOUR_PROJECT_REF
   supabase db push
   supabase functions deploy
   ```

2. Copy `supabase/.env.example` to `supabase/.env`, replace every used value,
   and upload secrets:

   ```sh
   supabase secrets set --env-file supabase/.env
   ```

3. In Supabase Auth, keep email confirmation enabled. Configure Google and
   Apple providers and allow this mobile redirect URL:

   ```text
   io.supabase.uniclub://login-callback
   ```

   For Apple, register `com.uniclub.app`, enable Sign in with Apple in the
   provisioning profile, and use the same service/bundle configuration in the
   Supabase Apple provider.

4. Copy `dart_defines.example.json` to the ignored `dart_defines.json`, place
   the project URL and **publishable/anon** key there, then run:

   ```sh
   flutter pub get
   flutter run --dart-define-from-file=dart_defines.json
   ```

   Never put the Supabase service-role key or third-party secrets in Flutter.

5. Create the first college row in Supabase Studio or SQL, create an account,
   then create a club from the app. Club creation automatically seeds all
   standard roles and makes the creator President.

## External provider contracts

The application is complete at the product/database layer, but live third-party
transactions cannot be activated without owner credentials and provider
accounts. The adapters intentionally return a clear `503` until configured.

- **Payments:** point `PAYMENT_CHECKOUT_ENDPOINT` at a PCI-compliant hosted
  checkout provider. It receives `reference`, `amount`, `currency`,
  `description`, and `customer_reference`, and must return `checkout_url` plus
  an optional provider payment ID. Configure the provider to call
  `payment-webhook` with `x-payment-webhook-secret`; the payload must include
  the internal `reference`, provider status, and optional invoice URL.
- **Push:** configure an FCM/APNs/OneSignal adapter using
  `PUSH_PROVIDER_ENDPOINT` and `PUSH_PROVIDER_API_KEY`. The adapter receives
  `token`, `title`, `body`, and `data`. Client token registration belongs in
  the selected provider's Flutter SDK because APNs and FCM credentials are
  app-owner specific.
- **Scheduled work:** schedule `dispatch-notifications` every minute from
  Supabase Cron with the `x-cron-secret` header. It publishes scheduled
  announcements, creates due reminder notifications, sends queued pushes, and
  records delivery time.

## Release configuration

### Android

The production ID is `com.uniclub.app`. Create `android/key.properties`
(ignored by Git):

```properties
storePassword=replace_me
keyPassword=replace_me
keyAlias=upload
storeFile=/absolute/path/to/upload-keystore.jks
```

Then build:

```sh
flutter build appbundle --release \
  --dart-define-from-file=dart_defines.json \
  --obfuscate --split-debug-info=build/symbols/android
```

Without `key.properties`, local release builds deliberately fall back to the
debug key for developer convenience; never upload that artifact.

### iOS

The bundle ID is `com.uniclub.app`. Select the production Apple team and
distribution profile in Xcode, configure the production APNs entitlement, then:

```sh
flutter build ipa --release \
  --dart-define-from-file=dart_defines.json \
  --obfuscate --split-debug-info=build/symbols/ios
```

## Verification

Run before every release:

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
```

For staging, test two normal students and two club officers through: verified
signup, OAuth, block/unblock, join approval, paid and free event
registration, waitlisting, QR/manual attendance, announcement scheduling,
mentions/messages, expense approval, reminder dispatch, account suspension,
and deletion. Also run Supabase's database advisor after every migration and
review RLS findings before promotion.

## Launch ownership checklist

- Add real college data and verify administrator accounts.
- Select payment and push vendors and provide their secrets.
- Configure Google and Apple OAuth production credentials.
- Configure the notification cron and provider callbacks.
- Replace template icons/screenshots and publish privacy/support URLs.
- Complete Play Console/App Store privacy declarations and content ratings.
- Create Android upload signing and Apple distribution credentials.
- Run the staging acceptance matrix above, database backup/restore rehearsal,
  and store review builds.
