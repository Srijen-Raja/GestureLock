Gesture Recognition & ML Pipeline

Pmod JSTK2 SPI Acquisition: Polls 10-bit X/Y joystick coordinates and 3 button states at 100 Hz over a 500 kHz SPI Mode 0 interface.

Hysteresis Stroke Segmentation: Detects stroke start (r > 60) and end (r < 40 for 400 ms dwell), drops trailing rest samples, filters out short/small taps (< 20 samples or < 150 radial extent), and buffers valid strokes in Block RAM.

16x16 Grid Rasterization: Normalizes buffered coordinates around the joystick rest center (528, 518) into a 256-bit binary image with midpoint interpolation between consecutive points.

7-Class Gesture Classification: Identifies **Circle, Down, Hline, Left, Right, Up, and Vline** gestures from the 16x16 bitmap.

Classifier Confidence Gating: Compares the top-1 and top-2 class logit scores and rejects ambiguous strokes that fall below a configurable margin threshold.

Lock Security & Master FSM

4-Gesture Sequence Verification: Evaluates a 4-shape password sequence (default: Circle → Left → Right → Vline) to unlock the system.

Reprogrammable Password Mode: Pressing ZedBoard BTNU while unlocked enters SET PASS mode, allowing 4 new shapes to be drawn and saved as the active password.

Tap-to-Undo: A short press-and-release (5 ms to 300 ms) of any joystick button while entering shapes clears the most recently filled box.

1-Second Hold-to-Lock: Stays unlocked until any Pmod JSTK2 button is held continuously for 1.0 second, preventing accidental re-locking.

Timed Evaluation & Reset Flow: Displays LOCKED for 1.0 second on boot or BTNC reset, pauses 500 ms after the 4th gesture so the final shape can be previewed before evaluation, and holds WRONG! for 1.0 second before resetting.

SSD1306 OLED UI & Hardware Integration

Live 4-Box Shape Rendering: Displays four 24x24 frames side-by-side and renders the user's exact 16x16 rasterized drawing inside each box sequentially.

3x-Scaled Status Banners: Displays centered, 180°-rotated banners (LOCKED, UNLOCKED, WRONG!, SET PASS, SAVED!) using a 3x-scaled 5x7 font.

Visual Border Animations: Blinks the active box border while drawing, flashes a double border for 300 ms when a stroke is rejected for size or low confidence, and adds top/bottom dashed bars during password programming.

Zero-LED Operation: All ZedBoard user LEDs (LD0–LD7) and Pmod JSTK2 RGB LED outputs are removed so only the OLED display provides visual feedback.
