# Object Detection & Distance Estimation Methodology

This document explains the technical implementation of the two core sensing modalities and how they are combined to produce spoken alerts.

---

## 1. Camera Frame Acquisition

The system opens the USB webcam using OpenCV's V4L2 backend:

```python
cap = cv2.VideoCapture(0, cv2.CAP_V4L2)
cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
```

**Frame skip**: To balance detection throughput with Raspberry Pi CPU load, only every second frame is processed:

```python
FRAME_SKIP = 2
if frame_count % FRAME_SKIP != 0:
    continue
```

At a webcam output of ~15–30 fps, this results in approximately 7–15 processed detections per second before inference time.

---

## 2. HC-SR04 Distance Measurement

### Operating Principle

The HC-SR04 sensor emits a 40 kHz ultrasonic pulse and measures the time for the echo to return. The microcontroller interface involves:

1. Drive TRIG HIGH for 10 µs to trigger a burst.
2. Measure the duration the ECHO pin remains HIGH.
3. Compute distance: `distance_cm = duration_s × 17150`

The constant 17150 = (speed of sound / 2) × 100, calculated as (343 m/s / 2) × 100 cm/m ≈ 17150 cm/s.

### Timeout Handling

```python
if pulse_start - timeout > 0.03:   # 30 ms timeout
    return 999
```

If no echo returns within 30 ms, the function returns 999 cm. This handles:
- Open spaces with no reflective surface within range
- Soft, sound-absorbing surfaces (fabric, carpet)
- Objects outside the ~15° beam angle

### Proximity Zones

The 999 cm timeout value falls into the "far" category, which generates no warning for open space ahead.

| Zone | Threshold | Spoken suffix |
|:---|:---|:---|
| **near** | distance_cm < 80 | "near" |
| **medium** | 80 ≤ distance_cm < 200 | "medium" |
| **far** | distance_cm ≥ 200 | "far" |

> **Accuracy note**: These thresholds are practical tuning values. The HC-SR04 has a nominal accuracy of ±3 mm under ideal conditions, but in outdoor or irregular environments error may be 5–10%. The zones are intentionally coarse to accommodate this uncertainty.

---

## 3. TFLite Model and Preprocessing

### Model

The system uses the **SSD MobileNet v1 COCO** quantised TFLite model (`detect.tflite`). Key properties:

| Property | Value |
|:---|:---|
| Architecture | Single Shot Detector (SSD) |
| Backbone | MobileNet v1 |
| Input size | 300×300 px (read dynamically from `input_details`) |
| Input dtype | uint8 (quantised) |
| Output | boxes, class indices, confidence scores, count |
| Classes | 80 COCO classes |
| Model source | TensorFlow Model Zoo |

### Frame Preprocessing

```python
frame_resized = cv2.resize(frame, (width, height))   # → 300×300
input_data = np.expand_dims(frame_resized, axis=0)   # → [1, 300, 300, 3]
```

The frame is resized from 640×480 to the model's input dimensions without normalisation. The quantised model accepts uint8 values (0–255) directly.

---

## 4. Inference and Output Tensors

```python
interpreter.set_tensor(input_details[0]['index'], input_data)
interpreter.invoke()

boxes   = interpreter.get_tensor(output_details[0]['index'])[0]   # [N, 4]
classes = interpreter.get_tensor(output_details[1]['index'])[0]   # [N]
scores  = interpreter.get_tensor(output_details[2]['index'])[0]   # [N]
```

The SSD model outputs up to N candidate detections (typically N=10 for the lite model). Each detection consists of:
- **boxes**: Normalised `[ymin, xmin, ymax, xmax]` in range [0, 1]
- **classes**: Float class index (cast to int for label lookup)
- **scores**: Confidence score in range [0, 1]

---

## 5. Post-Processing Filters

### 5.1 Confidence Threshold

```python
CONFIDENCE_THRESHOLD = 0.6
if scores[i] < CONFIDENCE_THRESHOLD:
    continue
```

Only detections with ≥ 60% confidence are considered. This was tuned empirically to balance detection rate against false positives.

### 5.2 Label Lookup

```python
object_name = labels[class_id + 1]
```

The labelmap uses a blank first row (`???`) at index 0, requiring `class_id + 1` to index the correct label. This is the standard format for the COCO SSD MobileNet TFLite model as distributed by TensorFlow.

### 5.3 Bounding Box Pixel Coordinates

```python
ymin = int(max(1, boxes[i][0] * imH))
xmin = int(max(1, boxes[i][1] * imW))
ymax = int(min(imH, boxes[i][2] * imH))
xmax = int(min(imW, boxes[i][3] * imW))
```

Normalised coordinates are converted to pixel coordinates on the 640×480 frame. Values are clamped to within the frame boundaries.

### 5.4 Minimum Box Area Filter

```python
box_area = (xmax - xmin) * (ymax - ymin)
if box_area < 3000:
    continue
```

Rejects very small bounding boxes (e.g. distant background objects). 3000 px² corresponds approximately to a 55×55 pixel box on a 640×480 frame — roughly 1% of frame area.

### 5.5 Centre Alignment Filter

```python
margin = 120
if object_name != "person":
    if not (xmin - margin < center_x < xmax + margin):
        continue
```

Non-person objects must be within 120 pixels of the horizontal centre of the frame. This focuses detection on objects directly in the user's path of travel and reduces alerts from peripheral objects. Persons are always reported regardless of position.

### 5.6 Ignore List

```python
ignored_objects = ["suitcase"]
if object_name in ignored_objects:
    continue
```

The `suitcase` class was observed to produce frequent false positives in testing and is excluded.

---

## 6. Object Priority and Selection

Only one object is announced per voting cycle. Selection priority:

```python
if object_name == "person":
    box_area += 1000000   # Person always wins

if box_area > best_area:
    best_area = box_area
    best_object = object_name
    best_box = (xmin, ymin, xmax, ymax)
```

Persons always take priority. Among non-person objects, the largest bounding box (by pixel area) is selected. This heuristic selects the nearest and most prominent object in the frame.

> **Limitation**: Bounding-box area is not a calibrated distance measurement. It depends on the object's physical size and aspect ratio. A large distant object may appear to have the same box area as a small nearby object. The HC-SR04 is used for actual distance measurement; box area is used only for selection priority.

---

## 7. Temporal Voting System

```python
VOTING_WINDOW = 1.5    # seconds
MIN_DETECTIONS = 3

detections_buffer.append(best_object)

if current_time - vote_start_time >= VOTING_WINDOW:
    if len(detections_buffer) >= MIN_DETECTIONS:
        object_counter = Counter(detections_buffer)
        most_common = object_counter.most_common(1)[0][0]
        count = object_counter.most_common(1)[0][1]
        if count >= MIN_DETECTIONS:
            # → trigger audio
```

Detection stability is enforced by requiring the same object class to appear at least 3 times in any 1.5-second window. This eliminates single-frame false positives that would generate spurious audio. The buffer is reset after each voting window.

---

## 8. Audio Output

### Object Grouping

```python
if most_common == "person":
    speak(f"Person {distance_status}")
elif most_common in ["car", "bus", "truck"]:
    speak(f"Vehicle {distance_status}")
elif most_common in ["dog", "cat", "cow", "horse"]:
    speak(f"Animal {distance_status}")
else:
    speak(most_common + " " + distance_status)
```

Semantically similar object classes are grouped to simplify the audio output. A user hearing "Vehicle near" does not need to distinguish between a car and a bus in real-time navigation.

### Cooldown

```python
COOLDOWN = 4  # seconds

if (final_message != last_spoken or
    current_time - last_speak_time > COOLDOWN):
    speak(...)
    last_spoken = final_message
    last_speak_time = current_time
```

A 4-second cooldown prevents the same message from repeating unnecessarily. If the object or zone changes, a new message is spoken immediately regardless of cooldown.

### TTS Execution

```python
def speak(text):
    print("SPEAK:", text)
    os.system(
        f'espeak-ng -s 150 "{text}" > /tmp/tts.wav && aplay /tmp/tts.wav'
    )
```

eSpeak-NG synthesises speech at 150 words per minute and writes to a temporary WAV file. `aplay` plays the file via ALSA to the audio output device (earphones connected to the 3.5 mm jack).

> **Limitation**: The `os.system()` call is synchronous and blocks the main loop until audio playback completes. For short phrases ("Person near" is approximately 0.5 s), this is acceptable. Long announcements would introduce perceptible detection lag.

---

## 9. What Has Not Been Measured

The following performance metrics are cited in some assistive technology research but are **not measured** in this prototype:

- Detection accuracy (mAP) — not benchmarked; the standard COCO SSD MobileNet v1 model has published mAP of ~23 on the COCO validation set
- Inference latency — not measured; expected ~150–300 ms per frame on Raspberry Pi 4 for INT8 model
- End-to-end system latency — not measured
- Distance measurement accuracy vs ground truth — not benchmarked
- False positive rate — not measured; qualitatively observed to be low with the voting system

These metrics would require controlled test apparatus and are identified as future work.
