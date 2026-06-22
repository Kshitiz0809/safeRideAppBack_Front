---
title: SafeRider Backend
emoji: 🏍
colorFrom: blue
colorTo: red
sdk: docker
pinned: false
app_port: 7860
---

# SafeRider Backend API

REST API for the SafeRider rash-driving detection app. Accepts per-window telemetry, runs a trained ML scoring model (GradientBoostingRegressor), and returns an overall ride safety score (0–100).

## Endpoints

- `GET /health` — health check, confirms model load status
- `POST /sync` — sync telemetry windows

## POST /sync payload

```json
{
  "ride_id": "uuid",
  "user_id": "firebase-uid",
  "windows": [
    {
      "speed": 45.5,
      "max_roll": 12.3,
      "max_cornering_intensity": 98.5,
      "jerk_variance": 8.2,
      "window_score": 92.1
    }
  ]
}
```
