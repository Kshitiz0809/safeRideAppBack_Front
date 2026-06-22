# SafeRider

Offline-first two-wheeler rash-driving detection system. A Flutter app collects ride telemetry (GPS, accelerometer, gyroscope) on-device, derives kinematic features (cornering intensity, jerk variance, roll), and syncs windows to a FastAPI backend that scores ride safety (0–100) using a trained GradientBoostingRegressor model.

## Structure

- [`saferider/`](saferider/) — Flutter frontend: telemetry capture, offline-first SQLite storage, Riverpod state management, Firebase auth/sync.
- [`backend/`](backend/) — FastAPI backend: `/sync` and `/health` endpoints, ML scoring model (`backend/model/`).

## Getting started

See [`saferider/README.md`](saferider/README.md) for the Flutter app and [`backend/README.md`](backend/README.md) for the API.
