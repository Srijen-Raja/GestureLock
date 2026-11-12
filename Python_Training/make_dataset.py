"""strokes.csv -> dataset.npz (images + labels) for CNN training.
Each stroke (all rows with one stroke_id) becomes one IMG x IMG image.
Steps: resample by arc length -> fixed-frame normalise (rest centre, gate radius) -> draw lines.
"""
import numpy as np, pandas as pd

IMG = 16          # image size (16 or 28)
CX, CY = 528.0, 518.0   # stick rest centre in raw counts (measured rest: ~522-530, 517-522)
SCALE = 375.0           # counts from centre to the rim of the gate (measured ~375)
NPTS = 64         # points per stroke after resampling
PAD = 1           # pixel border

def resample(xy, n):
    seg = np.hypot(*np.diff(xy, axis=0).T)
    s = np.r_[0, np.cumsum(seg)]
    if s[-1] == 0:
        return np.repeat(xy[:1], n, axis=0)
    u = np.linspace(0, s[-1], n)
    return np.c_[np.interp(u, s, xy[:, 0]), np.interp(u, s, xy[:, 1])]

def normalise(xy):
    """Fixed frame: origin = stick rest centre, 1.0 = rim of the gate.
    Keeps WHERE a stroke is (left of centre vs right of centre), not just its shape."""
    p = (xy - np.array([CX, CY])) / SCALE
    return np.clip(p, -1.0, 1.0)

def rasterise(xy):
    img = np.zeros((IMG, IMG), np.uint8)
    p = (xy + 1) / 2 * (IMG - 1 - 2 * PAD) + PAD
    p[:, 1] = (IMG - 1) - p[:, 1]              # joystick up = image up
    for a, b in zip(p[:-1], p[1:]):
        for t in np.linspace(0, 1, 8):
            q = a + (b - a) * t
            img[int(round(q[1])), int(round(q[0]))] = 1
    return img

def main():
    s = pd.read_csv('strokes.csv')
    labels = sorted(s.label.unique())
    X, y, ids = [], [], []
    for sid, g in s.groupby('stroke_id'):
        xy = g[['x', 'y']].values.astype(float)
        img = rasterise(normalise(resample(xy, NPTS)))
        X.append(img); y.append(labels.index(g.label.iloc[0])); ids.append(sid)
    X = np.array(X)[:, None]                   # N x 1 x IMG x IMG
    np.savez('dataset.npz', X=X, y=np.array(y), ids=np.array(ids),
             session=s.groupby('stroke_id').session.first().values,
             labels=np.array(labels))
    print(f"{len(X)} strokes, classes: {labels}, image shape {X.shape[1:]}")
    for i in range(min(3, len(X))):
        print(f"--- stroke {ids[i]} ({labels[y[i]]}) ---")
        print("\n".join("".join("#" if v else "." for v in r) for r in X[i, 0]))

if __name__ == '__main__':
    main()
