import serial, csv, time, os
from collections import deque
import statistics as st

COM_PORT = 'COM11'
BAUD = 115200
OUT = 'strokes.csv'
SESSION = 'session1'     # change per sitting or per person

START_RADIUS = 60        # stroke starts when stick is this far from rest (counts)
END_RADIUS = 40          # "back at rest" threshold (smaller than START = hysteresis)
DWELL_SAMPLES = 25       # ~250 ms at rest ends the stroke
MIN_SAMPLES = 20         # discard accidental touches
MIN_EXTENT = 150         # discard strokes that never get this far from rest

def main():
    ser = serial.Serial(COM_PORT, BAUD, timeout=1)
    ser.reset_input_buffer()

    # Estimate rest center from the first 1 s while you are not touching the stick
    print("Do not touch the stick for 1 second (calibrating rest center)...")
    cal_x, cal_y = [], []
    t_end = time.time() + 1.0
    while time.time() < t_end:
        p = ser.readline().decode('utf-8', errors='ignore').strip().split(',')
        if len(p) == 3:
            try:
                cal_x.append(int(p[0])); cal_y.append(int(p[1]))
            except ValueError:
                pass
    cx, cy = st.median(cal_x), st.median(cal_y)
    print(f"Rest center = ({cx}, {cy})")

    new = not os.path.exists(OUT)
    stroke_id = 0
    if not new:
        with open(OUT) as fh:
            ids = [int(r[0]) for r in csv.reader(fh) if r and r[0].isdigit()]
        stroke_id = (max(ids) + 1) if ids else 0

    f = open(OUT, 'a', newline='')
    w = csv.writer(f)
    if new:
        w.writerow(['stroke_id', 'label', 'session', 't_ms', 'x', 'y'])

    label = input("Shape label: ").strip()
    print(f"Draw '{label}', release the stick, wait half a second, repeat. Ctrl+C to stop.")

    active, buf, t0, rest_count, saved = False, [], 0.0, 0, 0

    try:
        while True:
            p = ser.readline().decode('utf-8', errors='ignore').strip().split(',')
            if len(p) != 3:
                continue
            try:
                x, y = int(p[0]), int(p[1])
            except ValueError:
                continue
            r = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5

            if not active:
                if r > START_RADIUS:
                    active, buf, t0, rest_count = True, [], time.time(), 0
                    buf.append((0, x, y))
            else:
                buf.append((int((time.time() - t0) * 1000), x, y))
                rest_count = rest_count + 1 if r < END_RADIUS else 0
                if rest_count >= DWELL_SAMPLES:
                    stroke = buf[:-DWELL_SAMPLES]          # drop the resting tail
                    extent = max(((a - cx) ** 2 + (b - cy) ** 2) ** 0.5 for _, a, b in stroke) if stroke else 0
                    if len(stroke) >= MIN_SAMPLES and extent >= MIN_EXTENT:
                        for t, xx, yy in stroke:
                            w.writerow([stroke_id, label, SESSION, t, xx, yy])
                        f.flush()
                        stroke_id += 1
                        saved += 1
                        print(f"saved stroke {saved}: {len(stroke)} samples")
                    else:
                        print(f"discarded ({len(stroke)} samples, extent {extent:.0f})")
                    active = False
    except KeyboardInterrupt:
        print(f"\nDone. {saved} strokes saved to {OUT}.")
    finally:
        f.close()
        ser.close()

main()