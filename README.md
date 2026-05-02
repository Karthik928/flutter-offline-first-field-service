# Field Service Management App

[![Flutter](https://img.shields.io/badge/Flutter-3.8+-02569B?logo=flutter)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/Dart-3.8+-0175C2?logo=dart)](https://dart.dev/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Project Overview

This Flutter application is a comprehensive field service management solution designed for mobile and desktop platforms. It enables field technicians to manage dealer visits, farmer interactions, order processing, expense tracking, and task assignments while maintaining full offline functionality. The app features real-time GPS tracking, automated background synchronization, and robust error handling to ensure data integrity in challenging network conditions.

## Technical Highlights

- **Failed Record Management System**: Implemented a sophisticated persistence layer using `FailedRecordStore` that captures and retries failed API requests, preventing data loss during connectivity issues and providing user visibility into synchronization status.
- **Offline-First Synchronization Engine**: Developed a custom `SyncService` with intelligent queuing, retry logic, and background processing via Workmanager, ensuring seamless data sync when connectivity is restored.
- **Background GPS Tracking Service**: Integrated continuous location monitoring using Geolocator and Workmanager, with battery-optimized sampling and secure storage for trip logging and compliance reporting.
- **HTTP Client with Caching and Interceptors**: Built a robust `ApiClient` with automatic caching, request queuing, and connectivity-aware retry mechanisms to handle intermittent network conditions.
- **State Management with Riverpod**: Leveraged Flutter Riverpod for scalable state management across complex workflows, including authentication, trip states, and offline data synchronization.
- **Cross-Platform Persistence**: Combined Hive for NoSQL key-value storage with SQLite for structured data, enabling efficient local storage across mobile and desktop platforms.

## Architecture

The application follows a feature-first architecture with clear separation of concerns, inspired by Clean Architecture principles. The codebase is organized into modular layers:

- **Presentation Layer** (`lib/Screens/`, `lib/zonal_Screens/`): UI screens and widgets, organized by feature domains (dealers, farmers, trips, etc.)
- **Business Logic Layer** (`lib/provider/`): Riverpod providers managing application state, authentication, and trip management
- **Data Layer** (`lib/services/`, `lib/offline/`): API clients, local storage services, and offline synchronization logic
- **Core Layer** (`lib/models/`, `lib/helpers/`): Data models, utility functions, and platform-specific helpers
- **Infrastructure Layer** (`lib/platform/`): Native platform integrations for location services and background tasks

This structure ensures maintainability, testability, and scalability while supporting both mobile and desktop deployments.

## Tech Stack

| Technology | Purpose | Notes |
|------------|---------|-------|
| Flutter | Cross-platform UI framework | Supports mobile, web, and desktop |
| Dart | Programming language | Version 3.8+ with null safety |
| Firebase | Backend services | Authentication, messaging, and cloud functions |
| Hive | Local NoSQL storage | Fast key-value storage for app state |
| SQLite (sqflite) | Structured local database | Complex data relationships and queries |
| Riverpod | State management | Reactive state management with dependency injection |
| HTTP | Network requests | RESTful API communication with caching |
| Google Maps Flutter | Mapping and location | Interactive maps and geocoding |
| Geolocator | GPS services | Location tracking and permissions |
| Workmanager | Background tasks | Scheduled sync and location updates |
| Connectivity Plus | Network monitoring | Offline/online state detection |
| Shared Preferences | Simple key-value storage | User settings and app configuration |

## Getting Started

### Prerequisites
- Flutter SDK 3.8 or higher
- Dart SDK 3.8 or higher
- Android Studio (for Android development) or Xcode (for iOS development)
- For Android: Android SDK API level 21 or higher
- For iOS: iOS 11.0 or higher

### Installation
1. **Clone the repository**:
   ```bash
   git clone https://github.com/Karthik928/flutter-offline-first-field-service.git
  cd flutter-offline-first-field-service
   ```

2. **Install dependencies**:
   ```bash
   flutter pub get
   ```

3. **Configure environment variables**:
   Create a `.env` file in the root directory or use `--dart-define` flags:
   ```bash
   flutter run --dart-define=API_BASE_URL=https://your-api-endpoint.com --dart-define=GOOGLE_MAPS_KEY=your-maps-api-key
   ```
   Replace `your-api-endpoint.com` and `your-maps-api-key` with actual values.

4. **Run the application**:
   ```bash
   flutter run
   ```

   For specific platforms:
   ```bash
   flutter run -d android  # For Android
   flutter run -d ios      # For iOS
   flutter run -d macos    # For macOS
   flutter run -d windows  # For Windows
   flutter run -d chrome   # For web
   ```

## Key Challenges Solved

- **Offline Data Synchronization**: Developed a robust queuing system that handles API failures gracefully, with exponential backoff retry logic and user notifications for failed operations, ensuring no data loss in poor connectivity areas.
- **Battery-Efficient GPS Tracking**: Implemented adaptive location sampling that balances accuracy with battery life, using background services to maintain continuous tracking during field operations.
- **Complex State Management**: Orchestrated multiple concurrent workflows (authentication, trip management, offline sync) using Riverpod, with proper error boundaries and loading states to maintain UI responsiveness.
- **Cross-Platform Compatibility**: Resolved platform-specific challenges in background processing and file system access, ensuring consistent behavior across Android, iOS, and desktop environments.
- **Data Integrity in Offline Scenarios**: Created a failed record recovery system that persists unsuccessful operations and provides manual retry options, preventing data corruption during network interruptions.

## Screens / Features

### Core Features
- **Dashboard**: KPI metrics, task assignments, and quick access to main functions
- **Dealer Management**: Visit scheduling, order processing, and lead tracking
- **Farmer Interactions**: On-site farmer registration and data collection
- **Trip Tracking**: GPS-based route logging and time tracking
- **Expense Management**: Receipt capture and expense reporting
- **Cart System**: Offline order management with local storage
- **Task Assignment**: Real-time task distribution and status updates

### Administrative Screens
- **Zonal Dashboard**: Regional oversight and performance analytics
- **Failed Records**: Manual retry interface for failed synchronizations
- **Sync Center**: Data synchronization status and conflict resolution
- **Settings**: App configuration and user preferences

### Additional Capabilities
- Push notifications for task updates
- Offline map caching for rural areas
- Image capture and upload for documentation
- Battery optimization prompts
- Multi-language support (planned)

---

*This project demonstrates advanced Flutter development techniques including offline-first architecture, background services, and cross-platform optimization. Built as a portfolio piece to showcase enterprise-level mobile application development skills.*