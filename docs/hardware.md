# Hardware Setup & Wiring Guide

This document covers the physical hardware components, GPIO pin assignments, circuit connections, and assembly considerations for the AI-Assisted Wearable Mobility Aid prototype.

---

## Component List

| Component | Model / Spec | Interface |
| :--- | :--- | :--- |
| Raspberry Pi 4 Model B | 4 GB RAM, BCM2711 | — |
| Raspberry Pi case | With cooling fan | — |
| USB webcam | UVC-compatible, e.g. Logitech C270 | USB 2.0 |
| HC-SR04 ultrasonic sensor | 2–400 cm range, 40 kHz | GPIO (BCM) |
| Resistors | 1 kΩ and 2 kΩ (for voltage divider) | GPIO ECHO |
| Earphones | 3.5 mm wired | Audio jack |
| Portable power bank | ~5 V, 4000–5000 mAh, USB-C output | USB-C |
| Jumper wires | Male-to-female | GPIO header |
| Fabric cap | For component mounting | — |

---

## Raspberry Pi 4 Setup

1. Flash **Raspberry Pi OS Lite (32-bit, Bookworm)** or **Raspberry Pi OS (32-bit, Bookworm)** to a ≥16 GB microSD card using Raspberry Pi Imager.
2. Enable SSH in Raspberry Pi Imager (or add an empty `ssh` file to the boot partition) for headless setup.
3. Connect the case cooling fan to the 5V / GND header pins if applicable.
4. Insert the microSD card and power via the USB-C port.

---

## USB Webcam

The system uses `cv2.VideoCapture(0, cv2.CAP_V4L2)` via the V4L2 Linux subsystem.

**Connection**: Plug the USB webcam into any USB 2.0 port on the Raspberry Pi.

**Verification**:
```bash
ls /dev/video*
# Expected output: /dev/video0
v4l2-ctl --list-devices
```

If the device appears as `/dev/video1` or higher (e.g. if the Raspberry Pi Camera Module is also present), update line 120 of `webcam_detect.py`:
```python
cap = cv2.VideoCapture(1, cv2.CAP_V4L2)  # Change index as needed
```

The script sets resolution to 640×480. Most UVC-compatible webcams support this. If your webcam does not, OpenCV will silently use its default resolution without error.

---

## HC-SR04 Ultrasonic Sensor Wiring

> ⚠️ **Critical**: The HC-SR04 ECHO pin outputs 5V. The Raspberry Pi GPIO pins are 3.3V tolerant only. Connecting 5V directly to a GPIO pin will damage the Pi. A voltage divider **must** be used.

### Voltage Divider for ECHO Pin

The ECHO output of the HC-SR04 is stepped down from 5V to ~3.3V using a simple resistor voltage divider:

```
HC-SR04 ECHO ──── R1 (1kΩ) ──── GPIO23 (ECHO input to Pi)
                                     │
                                  R2 (2kΩ)
                                     │
                                   GND
```

Voltage at GPIO23 = 5V × 2kΩ / (1kΩ + 2kΩ) = **3.33V** ✓

### Full Wiring Table

| HC-SR04 Pin | Connection | Raspberry Pi Pin |
| :---: | :--- | :---: |
| VCC | 5V power | Pin 2 (5V) |
| GND | Ground | Pin 6 (GND) |
| TRIG | Direct connection | GPIO24 — Pin 18 |
| ECHO | Via voltage divider (see above) | GPIO23 — Pin 16 |

### Pin assignments in code

```python
TRIG = 23   # BCM numbering → physical Pin 16
ECHO = 24   # BCM numbering → physical Pin 18
```

> **Note**: The code uses `GPIO.BCM` mode. Double-check that TRIG and ECHO are connected to the correct physical pins if you are using a Raspberry Pi GPIO reference card.

See the wiring diagram image in [`docs/images/circuit-design.jpeg`](images/circuit-design.jpeg) for a visual reference.

---

## Audio Output

**Connection**: Plug standard 3.5 mm wired earphones into the Raspberry Pi 4 audio jack.

**Audio configuration**: On Raspberry Pi OS Bookworm, the default ALSA output should route to the 3.5 mm jack. If audio plays through HDMI instead, run:

```bash
# List available audio cards
aplay -l

# Force 3.5mm analogue output (card 0, device 0 on most Pi 4 systems)
amixer cset numid=3 1
# Or use raspi-config → System Options → Audio → Headphones
```

The `speak()` function in the code uses:
```bash
espeak-ng -s 150 "<text>" > /tmp/tts.wav && aplay /tmp/tts.wav
```

This writes to `/tmp/tts.wav` and plays it immediately. `/tmp` is typically a tmpfs RAM disk on Raspberry Pi OS, which is fast and does not wear the microSD card.

---

## Wearable Cap Mounting

The prototype mounts components on a standard fabric baseball cap:

1. **USB webcam**: Attached to the peak of the cap using a small clamp or velcro strip, oriented forward.
2. **HC-SR04 sensor**: Mounted at the front of the cap, parallel to the brim, facing forward.
3. **Raspberry Pi 4 + case**: Mounted on the side or back of the cap using velcro or a custom clip. The case weight (~150 g including the Pi) should be distributed evenly.
4. **Power bank**: Carried in a belt pouch or jacket pocket; connected to the Raspberry Pi via a short USB-C cable routed under clothing.
5. **Cables**: Jumper wires and USB cables are secured with cable clips or routed under the cap lining.

> **Comfort note**: The current prototype is a proof-of-concept. Component weight and cable routing have not been ergonomically optimised.

---

## Power Considerations

| Device | Typical current draw |
| :--- | :--- |
| Raspberry Pi 4B (active load) | ~600–900 mA at 5V |
| USB Webcam | ~100–200 mA |
| HC-SR04 | ~15 mA |
| Cooling fan | ~100–200 mA |
| **Total** | ~1–1.5A |

A 4000 mAh power bank at 5V provides approximately **3–5 hours** of runtime depending on load and power bank efficiency.

Use a power bank with at least 2A USB output to avoid undervoltage throttling. The Raspberry Pi 4 requires a 5.1V/3A source for full performance; a high-quality 2A output is sufficient for typical loads.

---

## Absence of Components (Clarification)

| Component | Status |
| :--- | :--- |
| Raspberry Pi Camera Module V2 | **Not used** — USB webcam is the actual camera input |
| Microphone module | **Not connected** — speech recognition is not implemented |
| Bone-conduction headset | **Not used** — standard wired earphones are the audio output |
| GPS module | **Not connected** — not implemented |
| Additional GPIO peripherals | None beyond HC-SR04 |
