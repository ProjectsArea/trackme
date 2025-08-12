# TrackMe - Smart Location Tracking App

A modern Flutter application with Firebase authentication, real-time location tracking, and admin dashboard.

## Features

### 🔐 Authentication System
- **Splash Screen**: Animated welcome screen with app branding
- **User Registration**: Employee registration with name, department, email, and password
- **Email Verification**: Firebase email verification for secure access
- **Login System**: User and admin login with different access levels
- **Admin Panel**: Hardcoded admin credentials (admin@trackme.com / admin123)

### 🗺️ Location Tracking
- **Google Maps Integration**: Real-time location display
- **Background Tracking**: Continuous location updates even when app is minimized
- **Route Navigation**: Real road-following routes with Google Directions API
- **Search & Autocomplete**: Google Places integration for destination search
- **State Persistence**: Navigation state persists across app restarts

### 👨‍💼 Admin Dashboard
- **User Management**: View all registered users
- **Analytics**: User statistics and activity tracking
- **Modern UI**: Professional dashboard with cards and statistics
- **Real-time Data**: Live updates from Firestore database

## Setup Instructions

### 1. Firebase Configuration

#### Create Firebase Project
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Create a new project named "trackme-app"
3. Enable Authentication with Email/Password
4. Enable Firestore Database
5. Enable Google Maps API in Google Cloud Console

#### Android Configuration
1. Add your Android app to Firebase project
2. Download `google-services.json` and replace the placeholder in `android/app/`
3. Update the package name in `android/app/build.gradle` if needed

#### Web Configuration
1. Add your web app to Firebase project
2. Update the Firebase config in `web/index.html` with your actual project details

### 2. Google Maps API Key
1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Enable the following APIs:
   - Maps SDK for Android
   - Places API
   - Directions API
   - Geocoding API
3. Create an API key and replace it in:
   - `lib/map_screen.dart` (line with `_apiKey`)
   - `android/app/src/main/res/values/strings.xml`
   - `web/index.html`

### 3. Dependencies
The app uses the following key dependencies:
- `firebase_core`, `firebase_auth`, `firebase_database`, `cloud_firestore`
- `google_maps_flutter`, `google_places_flutter`
- `location`, `flutter_background_service`
- `permission_handler`, `flutter_local_notifications`
- `shared_preferences`, `http`

### 4. Build and Run
```bash
flutter pub get
flutter run
```

## App Flow

### User Journey
1. **Splash Screen** → App loads with animation
2. **Login Screen** → User enters credentials or registers
3. **Registration** → Employee details + email verification
4. **Map Screen** → Location tracking and navigation
5. **Background Service** → Continuous tracking when minimized

### Admin Journey
1. **Login Screen** → Admin credentials (admin@trackme.com / admin123)
2. **Admin Dashboard** → User management and analytics
3. **Logout** → Returns to login screen

## File Structure

```
lib/
├── main.dart                 # App entry point with Firebase init
├── splash_screen.dart        # Animated splash screen
├── map_screen.dart          # Main map and navigation functionality
├── auth/
│   ├── login_screen.dart    # User and admin login
│   └── registration_screen.dart # User registration
└── admin/
    └── admin_home_screen.dart # Admin dashboard
```

## Admin Credentials
- **Email**: admin@trackme.com
- **Password**: admin123

## Permissions Required

### Android Permissions
- `ACCESS_FINE_LOCATION` - Precise location tracking
- `ACCESS_COARSE_LOCATION` - Approximate location
- `ACCESS_BACKGROUND_LOCATION` - Background tracking
- `FOREGROUND_SERVICE` - Background service
- `POST_NOTIFICATIONS` - Navigation notifications

## Background Service

The app uses `flutter_background_service` to maintain location tracking when minimized:
- Sends heartbeat events every 30 seconds
- Shows persistent notification during navigation
- Handles app lifecycle changes

## State Persistence

Navigation state is saved using `shared_preferences`:
- Current navigation status
- Origin and destination coordinates
- Search panel visibility
- Route information

## Troubleshooting

### Common Issues
1. **Firebase not initialized**: Check `google-services.json` and Firebase config
2. **Location not working**: Ensure location permissions are granted
3. **Maps not loading**: Verify Google Maps API key is correct
4. **Background service issues**: Check Android foreground service permissions

### Debug Commands
```bash
flutter clean
flutter pub get
flutter run --debug
```

## Security Notes

- Admin credentials are hardcoded for demo purposes
- In production, implement proper admin authentication
- Use Firebase Security Rules for Firestore
- Enable Firebase App Check for additional security

## Future Enhancements

- [ ] Real-time user location sharing
- [ ] Route optimization
- [ ] Offline map support
- [ ] Push notifications
- [ ] User activity reports
- [ ] Department-wise analytics
- [ ] Export functionality
- [ ] Multi-language support

## License

This project is for educational and demonstration purposes.
