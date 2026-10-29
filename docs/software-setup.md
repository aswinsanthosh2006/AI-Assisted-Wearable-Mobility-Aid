# Software Installation & Setup Guide

This guide covers the full software setup for the AI-Assisted Wearable Mobility Aid on a Raspberry Pi 4B running Raspberry Pi OS Bookworm (32-bit).

> **Important**: All commands in this guide are intended for the Raspberry Pi terminal, not a Windows or macOS development machine. Commands marked `[UNVERIFIED IN CURRENT ENV]` were not tested in the available development environment and should be verified on physical hardware.

---

## Supported Platform

| Property | Value |
| :--- | :--- |
| Raspberry Pi model | Raspberry Pi 4 Model B, 4 GB RAM |
| Operating System | Raspberry Pi OS Bookworm (32-bit) |
| Python version | Python 3.11 (Bookworm default) |
| Virtual environment | `blind_env` |

---

## Step 1 — System Package Installation

Before installing Python packages, install the required system libraries:

```bash
sudo apt update && sudo apt upgrade -y

# OpenCV system dependencies
sudo apt install -y python3-dev libatlas-base-dev libjasper-dev libqtgui4 \
    libqt4-test libhdf5-dev libhdf5-serial-dev

# Audio: espeak-ng TTS engine and ALSA playback
sudo apt install -y espeak-ng alsa-utils

# RPi.GPIO (usually pre-installed on Raspberry Pi OS)
sudo apt install -y python3-rpi.gpio

# V4L2 utilities for camera diagnosis
sudo apt install -y v4l-utils
```

---

## Step 2 — Python Virtual Environment

```bash
# Navigate to the project directory
cd ~/AI-Assisted-Wearable-Mobility-Aid

# Create virtual environment
python3 -m venv blind_env

# Activate
source blind_env/bin/activate

# Upgrade pip
pip install --upgrade pip
```

---

## Step 3 — Install TFLite Runtime

The `tflite-runtime` package must be installed from a wheel compatible with your Python version and ARM architecture (armv7l for 32-bit Bookworm).

```bash
# For Python 3.11 on 32-bit Raspberry Pi OS (armv7l):
pip install tflite-runtime==2.14.0
```

If the above fails, download the wheel directly from the TensorFlow GitHub releases:

```bash
# Check your Python version and architecture first
python3 --version
uname -m  # Should output 'armv7l' for 32-bit

# Download the matching wheel from:
# https://github.com/google-coral/pycoral/releases
# or
# https://www.tensorflow.org/lite/guide/python
```

> `tflite_runtime` is a lightweight inference-only package (~500 KB). It is separate from the full TensorFlow library (~500 MB). Do not install `tensorflow` or `tensorflow-lite` — use `tflite-runtime` only.

---

## Step 4 — Install Python Packages

```bash
# With blind_env activated:
pip install -r requirements.txt
```

Expected packages installed:
- `opencv-python` — camera capture and image processing
- `numpy` — array manipulation for model tensors
- `tflite-runtime` — TFLite inference engine
- `RPi.GPIO` — GPIO control for the HC-SR04 sensor

---

## Step 5 — Download the TFLite Model

The `detect.tflite` model file is not committed to the repository. Download the standard SSD MobileNet v1 COCO quantised model:

```bash
mkdir -p model

wget https://storage.googleapis.com/download.tensorflow.org/models/tflite/coco_ssd_mobilenet_v1_1.0_quant_2018_06_29.zip \
    -O /tmp/model.zip

unzip /tmp/model.zip -d /tmp/model_extracted

cp /tmp/model_extracted/detect.tflite model/detect.tflite

# Clean up
rm /tmp/model.zip
rm -rf /tmp/model_extracted
```

The `model/labelmap.txt` file is already in the repository and matches this model's 80 COCO classes.

**Model properties** (SSD MobileNet v1 COCO quantised):
- Input: `[1, 300, 300, 3]` uint8 (RGB)
- Output: boxes, classes, scores, num_detections
- Quantised: INT8 weights (smaller and faster on ARM)

---

## Step 6 — Audio Configuration

### Test eSpeak-NG

```bash
espeak-ng -s 150 "System ready"
```

You should hear speech through the earphones connected to the 3.5 mm jack.

### Force analogue audio output (if HDMI takes priority)

```bash
# Option 1: via raspi-config (recommended)
sudo raspi-config
# → System Options → Audio → Headphones

# Option 2: via amixer
amixer cset numid=3 1    # 1 = headphones, 2 = HDMI
```

### Test aplay

```bash
espeak-ng -s 150 "Test audio" > /tmp/tts.wav && aplay /tmp/tts.wav
```

---

## Step 7 — Camera Verification

```bash
# List video devices
ls /dev/video*

# Check device capabilities
v4l2-ctl --list-devices
v4l2-ctl -d /dev/video0 --list-formats-ext

# Test capture (saves one frame as test.jpg)
fswebcam -d /dev/video0 -r 640x480 test.jpg
```

The script uses device index `0`. If your webcam appears as `/dev/video1`, update line 120 of `webcam_detect.py`:
```python
cap = cv2.VideoCapture(1, cv2.CAP_V4L2)
```

---

## Step 8 — GPIO Verification

With the HC-SR04 wired as described in [hardware.md](hardware.md):

```bash
# Quick GPIO test (requires RPi.GPIO)
python3 - <<'EOF'
import RPi.GPIO as GPIO
import time

TRIG, ECHO = 23, 24
GPIO.setmode(GPIO.BCM)
GPIO.setup(TRIG, GPIO.OUT)
GPIO.setup(ECHO, GPIO.IN)
GPIO.output(TRIG, False)
time.sleep(0.5)

GPIO.output(TRIG, True)
time.sleep(0.00001)
GPIO.output(TRIG, False)

t = time.time()
while GPIO.input(ECHO) == 0:
    if time.time() - t > 0.03: break
t1 = time.time()
while GPIO.input(ECHO) == 1:
    if time.time() - t1 > 0.03: break
t2 = time.time()

print(f"Distance: {round((t2 - t1) * 17150, 1)} cm")
GPIO.cleanup()
EOF
```

---

## Step 9 — Running the Application

```bash
# From the project root directory with blind_env activated:
source blind_env/bin/activate
python3 webcam_detect.py
```

- The system speaks **"System ready"** on startup.
- An OpenCV window displays the live camera feed with bounding boxes.
- Press **Q** in the OpenCV window to exit cleanly.
- Press **Ctrl+C** in the terminal; GPIO cleanup runs automatically.

> **Headless / SSH operation**: If running over SSH without a display, the `cv2.imshow()` call will fail. Remove or guard this call with a `DISPLAY` environment variable check for headless use.

---

## Auto-Start on Boot (Optional)

To run the system automatically without logging in:

```bash
# Create a systemd service file
sudo nano /etc/systemd/system/blind-assist.service
```

Paste:
```ini
[Unit]
Description=AI Blind Assistance System
After=network.target

[Service]
ExecStart=/home/pi/AI-Assisted-Wearable-Mobility-Aid/blind_env/bin/python3 \
    /home/pi/AI-Assisted-Wearable-Mobility-Aid/webcam_detect.py
WorkingDirectory=/home/pi/AI-Assisted-Wearable-Mobility-Aid
StandardOutput=journal
StandardError=journal
Restart=on-failure
User=pi
Environment=DISPLAY=:0

[Install]
WantedBy=multi-user.target
```

Enable:
```bash
sudo systemctl daemon-reload
sudo systemctl enable blind-assist.service
sudo systemctl start blind-assist.service
```

> Note: For headless systemd operation, the `cv2.imshow()` call in `webcam_detect.py` must be removed or disabled, as there is no X display available.

---

## Common Errors & Troubleshooting

| Error | Likely Cause | Fix |
| :--- | :--- | :--- |
| `Camera not accessible` | Webcam not detected or wrong index | Run `ls /dev/video*`; update capture index |
| `ModuleNotFoundError: No module named 'tflite_runtime'` | tflite-runtime not installed in active venv | `pip install tflite-runtime==2.14.0` |
| `RuntimeError: Failed to load delegate from libedgetpu.so.1` | Edge TPU delegate not available | Remove delegate options; use CPU inference |
| `RuntimeError: GPIO.setup: invalid direction` | RPi.GPIO not installed or wrong version | `sudo apt install python3-rpi.gpio` |
| No audio output | HDMI taking priority | `amixer cset numid=3 1` |
| `espeak-ng: command not found` | espeak-ng not installed | `sudo apt install espeak-ng` |
| `FileNotFoundError: model/detect.tflite` | Model not downloaded | Run Step 5 above |
| `IndexError: list index out of range` | `labelmap.txt` missing or wrong format | Verify file is present with blank first row |
| Ultrasonic always returns 999 | Voltage divider missing or ECHO pin wrong | Check wiring against hardware.md |

---

## Dependency Version Notes

Pinned versions in `requirements.txt` are based on compatibility with Raspberry Pi OS Bookworm (32-bit) and Python 3.11. If you encounter installation failures:

1. Try removing version pins and installing latest: `pip install opencv-python numpy tflite-runtime RPi.GPIO`
2. Check Raspberry Pi-specific build notes for OpenCV: some versions require `libatlas-base-dev` to be installed first.
3. `opencv-python-headless` can replace `opencv-python` if a display is not available and binary size matters.
