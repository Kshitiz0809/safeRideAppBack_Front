import json
import os
from typing import Any, Dict, Iterable, List, Optional, Tuple

try:
    import firebase_admin
    from firebase_admin import auth, credentials, firestore
except ImportError:
    firebase_admin = None
    auth = None
    credentials = None
    firestore = None


FIREBASE_APP = None


def _initialize_firebase() -> None:
    global FIREBASE_APP
    if firebase_admin is None:
        return
    if FIREBASE_APP is not None:
        return
    if firebase_admin._apps:
        FIREBASE_APP = firebase_admin.get_app()
        return

    raw_service_account = os.environ.get("FIREBASE_SERVICE_ACCOUNT")
    if not raw_service_account:
        return

    try:
        service_account_info = json.loads(raw_service_account)
        cred = credentials.Certificate(service_account_info)
        FIREBASE_APP = firebase_admin.initialize_app(cred)
    except Exception as exc:
        print(f"Firebase Init Error: {exc}")


_initialize_firebase()

import pathlib
import numpy as np

_MODEL_DIR = pathlib.Path(__file__).resolve().parents[1] / "model"
_SCORE_MODEL = None
_SCORE_SCALER = None

try:
    import joblib as _joblib
    _SCORE_SCALER = _joblib.load(_MODEL_DIR / "scaler.pkl")
    _SCORE_MODEL = _joblib.load(_MODEL_DIR / "driving_score_model.pkl")
    print("ML scoring model loaded successfully.")
except Exception as _exc:
    print(f"ML model not available, using heuristic: {_exc}")


def _first_present(source: Dict[str, Any], keys: Iterable[str], default: Any = None) -> Any:
    for key in keys:
        if key in source and source[key] is not None:
            return source[key]
    return default


def _as_float(value: Any, field_name: str) -> float:
    if isinstance(value, bool) or value is None:
        raise ValueError(f"{field_name} must be a number")
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        raise ValueError(f"{field_name} must be a number")
    if parsed != parsed or parsed in (float("inf"), float("-inf")):
        raise ValueError(f"{field_name} must be finite")
    return parsed


def _clamp(value: float, lower: float, upper: float) -> float:
    return max(lower, min(upper, value))


def _normalize_window(raw_window: Dict[str, Any], index: int) -> Dict[str, Any]:
    if not isinstance(raw_window, dict):
        raise ValueError(f"windows[{index}] must be an object")

    speed = _as_float(_first_present(raw_window, ("speed",), 0.0), f"windows[{index}].speed")
    max_roll = _as_float(
        _first_present(raw_window, ("max_roll", "maxRoll"), 0.0),
        f"windows[{index}].max_roll",
    )
    max_cornering_intensity = _as_float(
        _first_present(raw_window, ("max_cornering_intensity", "maxCorneringIntensity"), 0.0),
        f"windows[{index}].max_cornering_intensity",
    )
    jerk_variance = _as_float(
        _first_present(raw_window, ("jerk_variance", "jerkVariance"), 0.0),
        f"windows[{index}].jerk_variance",
    )
    window_score = _as_float(
        _first_present(raw_window, ("window_score", "windowScore"), 100.0),
        f"windows[{index}].window_score",
    )

    return {
        "id": _first_present(raw_window, ("id", "windowId")),
        "timestamp": _first_present(raw_window, ("timestamp", "created_at", "createdAt")),
        "ride_id": _first_present(raw_window, ("ride_id", "rideId")),
        "user_id": _first_present(raw_window, ("user_id", "userId")),
        "speed": _clamp(speed, 0.0, 300.0),
        "max_roll": _clamp(abs(max_roll), 0.0, 180.0),
        "max_cornering_intensity": max(0.0, max_cornering_intensity),
        "jerk_variance": max(0.0, jerk_variance),
        "window_score": _clamp(window_score, 0.0, 100.0),
    }


def _percentile(sorted_values: List[float], percentile: float) -> float:
    if not sorted_values:
        return 0.0
    if len(sorted_values) == 1:
        return sorted_values[0]

    rank = (len(sorted_values) - 1) * percentile
    lower_index = int(rank)
    upper_index = min(lower_index + 1, len(sorted_values) - 1)
    fraction = rank - lower_index
    return sorted_values[lower_index] + (sorted_values[upper_index] - sorted_values[lower_index]) * fraction


def _average(values: List[float]) -> float:
    return sum(values) / len(values) if values else 0.0


def _extract_ride_features(windows: List[Dict[str, Any]]) -> "np.ndarray":
    # Feature order must match training: avg_speed, max_roll, avg_jerk,
    # harsh_windows, distance, duration
    speeds = [w["speed"] for w in windows]
    avg_speed = _average(speeds)
    max_roll = max(w["max_roll"] for w in windows)
    avg_jerk = _average([w["jerk_variance"] for w in windows])
    harsh_count = sum(
        1 for w in windows
        if w["window_score"] < 60.0
        or w["jerk_variance"] > 25.0
        or w["max_cornering_intensity"] > 120.0
    )
    duration_min = len(windows) * 3.0 / 60.0
    distance_km = avg_speed * (duration_min / 60.0)

    return np.array(
        [[avg_speed, max_roll, avg_jerk, harsh_count, distance_km, duration_min]],
        dtype=np.float64,
    )


def _calculate_ride_score(windows: List[Dict[str, Any]]) -> Dict[str, Any]:
    scores = [window["window_score"] for window in windows]
    speeds = [window["speed"] for window in windows]
    rolls = [window["max_roll"] for window in windows]
    cornering = [window["max_cornering_intensity"] for window in windows]
    jerk_variances = [window["jerk_variance"] for window in windows]

    sorted_scores = sorted(scores)
    avg_window_score = _average(scores)
    p10_score = _percentile(sorted_scores, 0.10)

    harsh_windows = sum(
        1
        for window in windows
        if window["window_score"] < 60.0
        or window["jerk_variance"] > 25.0
        or window["max_cornering_intensity"] > 120.0
    )
    harsh_ratio = harsh_windows / len(windows)

    if _SCORE_MODEL is not None and _SCORE_SCALER is not None:
        try:
            features = _extract_ride_features(windows)
            features_scaled = _SCORE_SCALER.transform(features)
            raw = float(_SCORE_MODEL.predict(features_scaled)[0])
            # Training target was 0–75; app expects 0–100.
            overall_score = round(_clamp(raw * (100.0 / 75.0), 0.0, 100.0), 1)
        except Exception as exc:
            print(f"ML prediction failed, using heuristic: {exc}")
            overall_score = round(
                _clamp(
                    (avg_window_score * 0.85) + (p10_score * 0.15) - (harsh_ratio * 10.0),
                    0.0, 100.0,
                ),
                1,
            )
    else:
        overall_score = round(
            _clamp(
                (avg_window_score * 0.85) + (p10_score * 0.15) - (harsh_ratio * 10.0),
                0.0, 100.0,
            ),
            1,
        )

    return {
        "overallScore": overall_score,
        "summary": {
            "windowCount": len(windows),
            "avgWindowScore": round(avg_window_score, 1),
            "lowestWindowScore": round(min(scores), 1),
            "maxRoll": round(max(rolls), 1),
            "avgSpeed": round(_average(speeds), 1),
            "maxSpeed": round(max(speeds), 1),
            "maxCorneringIntensity": round(max(cornering), 1),
            "maxJerkVariance": round(max(jerk_variances), 1),
            "harshWindowCount": harsh_windows,
        },
    }


def _store_ride_result(
    ride_id: str,
    user_id: Optional[str],
    normalized_windows: List[Dict[str, Any]],
    result: Dict[str, Any],
) -> None:
    if FIREBASE_APP is None or firestore is None:
        return

    try:
        db = firestore.client()
        payload = {
            "rideId": ride_id,
            "userId": user_id,
            "score": result["overallScore"],
            "summary": result["summary"],
            "windowCount": len(normalized_windows),
            "updatedAt": firestore.SERVER_TIMESTAMP,
        }
        db.collection("rides").document(ride_id).set(payload, merge=True)
    except Exception as exc:
        print(f"Firestore Save Error: {exc}")


def _verify_bearer_token(headers: Any) -> Optional[Dict[str, Any]]:
    auth_header = headers.get("Authorization", "")
    if not auth_header.startswith("Bearer ") or FIREBASE_APP is None or auth is None:
        return None

    token = auth_header.split(" ", 1)[1].strip()
    if not token:
        return None

    try:
        return auth.verify_id_token(token)
    except Exception as exc:
        print(f"Firebase Token Verification Error: {exc}")
        return None


def _process_sync_payload(payload: Dict[str, Any], headers: Any) -> Tuple[Dict[str, Any], int]:
    raw_windows = payload.get("windows")
    if not isinstance(raw_windows, list) or not raw_windows:
        return {"status": "error", "error": "windows must be a non-empty array"}, 400

    try:
        normalized_windows = [_normalize_window(window, index) for index, window in enumerate(raw_windows)]
    except ValueError as exc:
        return {"status": "error", "error": str(exc)}, 400

    decoded_token = _verify_bearer_token(headers)
    token_user_id = decoded_token.get("uid") if decoded_token else None
    ride_id = _first_present(payload, ("ride_id", "rideId")) or normalized_windows[0].get("ride_id")
    user_id = _first_present(payload, ("user_id", "userId")) or token_user_id or normalized_windows[0].get("user_id")

    if not ride_id:
        ride_id = f"anonymous-{normalized_windows[0].get('id') or payload.get('timestamp') or 'ride'}"

    result = _calculate_ride_score(normalized_windows)
    result.update(
        {
            "status": "success",
            "rideId": ride_id,
            "userId": user_id,
            "authVerified": decoded_token is not None,
        }
    )

    _store_ride_result(ride_id, user_id, normalized_windows, result)
    return result, 200


from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

app = FastAPI(title="SafeRider Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "Accept"],
    max_age=86400,
)


@app.get("/")
@app.get("/health")
async def health() -> Dict[str, Any]:
    return {
        "status": "ok",
        "service": "SafeRide backend",
        "firebaseConfigured": FIREBASE_APP is not None,
        "mlModelLoaded": _SCORE_MODEL is not None,
        "endpoints": {
            "POST /sync": "sync telemetry windows",
            "GET /health": "health check",
        },
    }


async def _parse_body(request: Request) -> Tuple[Optional[Dict[str, Any]], Optional[str]]:
    try:
        payload = await request.json()
    except Exception:
        return None, "Request body must be valid JSON"
    if not isinstance(payload, dict):
        return None, "Request body must be a JSON object"
    return payload, None


@app.post("/")
@app.post("/sync")
@app.post("/api/sync")
async def sync(request: Request) -> JSONResponse:
    payload, error = await _parse_body(request)
    if error:
        return JSONResponse({"status": "error", "error": error}, status_code=400)
    result, status_code = _process_sync_payload(payload, dict(request.headers))
    return JSONResponse(result, status_code=status_code)
