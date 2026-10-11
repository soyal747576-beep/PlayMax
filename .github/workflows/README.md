# Play MAX: player app (Flutter)

Players sign up and sign in with Firebase Authentication (phone number + password), join matches, see room details,
results, the leaderboard and their wallet. The server and admin panel are in the other package (`playmax_server_admin`).

## Screens
Sign in / Create account (two clear tabs at the top, with show-password and optional referral code), Home (banners and quick
access tiles), Play (upcoming, live and results tabs), match page with Join, My matches, Wallet, Profile, Leaderboard, Refer and earn.
Not included: Lucky Draw, Shop and Watch and Earn.

## Firebase setup (do this once)
1. Open Firebase Console > project `royalx11-dfffe` > Authentication > Get started.
2. Sign-in method > turn ON "Email/Password". The app signs players up as `<phone>@playmax.app`, so this must be on.
   If it is off, Sign up fails with "Email/Password sign-in is turned off in Firebase".
3. Google Cloud Console > APIs and Services > Credentials > your Browser key: it must not block Android/REST requests.
   If you added restrictions, allow the "Identity Toolkit API" and "Token Service API".
4. Keep database and storage rules closed (never "allow read, write: if true"). This app does not use them.

The Firebase settings are in `lib/firebase_config.dart`. Analytics is not included because it is not needed for sign-in.

## Build the APK for free (GitHub Actions)
1. Open `lib/main.dart` and set `kBaseUrl` (top of the file) to your server address, for example `https://your-server.com`.
2. Create a private GitHub repository and upload everything in this folder, including `.github`.
3. Go to Actions, choose "Build APK", press "Run workflow".
4. When it finishes, download `play-max-apk` from the run's Artifacts. It contains `app-release.apk`.

## Build on your own computer
```
flutter create --org com.playmax --project-name play_max .
flutter build apk --release
```
Keep our `lib/` folder and `pubspec.yaml` (copy them back if `flutter create` replaces them).
Make sure `android/app/src/main/AndroidManifest.xml` has `<uses-permission android:name="android.permission.INTERNET"/>`.
