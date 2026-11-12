"""Bit-exact Python model of what the FPGA does: stroke -> 16x16 image -> single-layer classifier.
Run in the RC folder (needs strokes.csv, export_linear/ from export_linear.py, make_dataset.py, train_cnn.py):
    python hw_model_linear.py
It tells you how well the HARDWARE algorithm works on your strokes, before you program the board.
"""
import numpy as np
from make_dataset import CX, CY, SCALE, resample, normalise, rasterise, NPTS
import train_cnn as T

CXI, CYI, SC = int(CX), int(CY), int(SCALE)
K = 18175                          # round(6.5 * 256 / 375 * 4096): counts -> pixels in Q8

def pix_q8(x, y):                  # matches stroke_raster.v
    ux = max(-SC, min(SC, x - CXI)); uy = max(-SC, min(SC, y - CYI))
    return 1920 + ((ux * K) >> 12), 1920 - ((uy * K) >> 12)      # >> on negative ints floors, like >>> in Verilog

def raster_hw(pts):                # matches stroke_raster.v
    img = np.zeros((16, 16), np.int64)
    plot = lambda px, py: img.__setitem__(((py + 128) >> 8, (px + 128) >> 8), 1)
    pa = pix_q8(*pts[0]); plot(*pa)
    for p in pts[1:]:
        pb = pix_q8(*p); dx, dy = pb[0] - pa[0], pb[1] - pa[1]
        for k in range(1, 17):
            plot(pa[0] + ((dx * k) >> 4), pa[1] + ((dy * k) >> 4))
        pa = pb
    return img

def detect_hw(samples, dwell=40, start_r2=3600, end_r2=1600, min_samples=20, min_extent2=22500, maxlen=1024):
    out, active = [], False         # matches stroke_detect.v
    for x, y in samples:
        r2 = (x - CXI) ** 2 + (y - CYI) ** 2
        if not active:
            if r2 > start_r2: active, buf, rest, maxr2 = True, [(x, y)], 0, r2
        else:
            buf.append((x, y)); maxr2 = max(maxr2, r2)
            if r2 < end_r2:
                rest += 1
                if rest >= dwell:
                    active = False; fl = len(buf) - dwell
                    if min_samples <= fl <= maxlen and maxr2 >= min_extent2: out.append(buf[:fl])
            else: rest = 0
    return out

def load_linear(d='export_linear'):
    def rd(fn, bits):
        v = [int(t, 16) for t in open(f'{d}/{fn}').read().split()]
        return np.array([a - (1 << bits) if a >= 1 << (bits - 1) else a for a in v], np.int64)
    b = rd('linear_b.mem', 32)
    return rd('linear_w.mem', 8).reshape(len(b), 256), b

def scores(img, W, b):             # matches linear_classifier.v
    return W @ img.reshape(-1) + b

def main():
    W, b = load_linear(); C = len(b)
    strokes, y, names = T.load_strokes()
    print("classes:", names)
    T.rng = np.random.default_rng(T.SEED); tr, va, te = T.split(y)        # same split as export_linear.py
    istest = np.zeros(len(y), bool); istest[te] = True
    diff, pred = [], []
    for s in strokes:
        pts = [(int(a), int(c)) for a, c in s]
        hw = raster_hw(pts)
        diff.append(int((hw != rasterise(normalise(resample(s, NPTS)))).sum()))
        pred.append(int(np.argmax(scores(hw, W, b))))
    diff, pred = np.array(diff), np.array(pred)
    print(f"\nimage check, hardware rasteriser vs the images the model was trained on ({len(diff)} strokes):")
    print(f"  identical: {np.mean(diff == 0) * 100:.1f}%   mean differing pixels: {diff.mean():.2f}   worst: {diff.max()}")
    for label, m in (("test strokes (not used in training)", istest), ("all strokes", np.ones(len(y), bool))):
        print(f"\nhardware-algorithm accuracy on {label}: {np.mean(pred[m] == y[m]):.3f}  ({int((pred[m] == y[m]).sum())}/{int(m.sum())})")
    cm = np.zeros((C, C), int)
    for t, p in zip(y[istest], pred[istest]): cm[t, p] += 1
    print("confusion matrix on the test strokes (rows = true, columns = predicted):"); print(cm)

if __name__ == '__main__':
    main()
