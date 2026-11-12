"""Train a small CNN on strokes.csv (needs make_dataset.py in the same folder).
Usage: python train_cnn.py
Requires: numpy, pandas, torch  (pip install torch)
"""
import numpy as np, pandas as pd
from make_dataset import resample, normalise, rasterise, NPTS, IMG

SEED = 0
TARGET_PER_CLASS = 400     # training images per class after augmentation
EPOCHS = 60
BATCH = 64
LR = 2e-3
rng = np.random.default_rng(SEED)

# ---------- data ----------
def load_strokes(path='strokes.csv'):
    s = pd.read_csv(path)
    s['label'] = s['label'].astype(str).str.lower().str.strip()
    strokes, labels = [], []
    for _, g in s.groupby('stroke_id'):
        strokes.append(g[['x', 'y']].values.astype(float))
        labels.append(g['label'].iloc[0])
    names = sorted(set(labels))
    return strokes, np.array([names.index(l) for l in labels]), names

def split(y, fr=(0.7, 0.15, 0.15)):
    """Stratified split BY STROKE, done before any augmentation (no leakage)."""
    tr, va, te = [], [], []
    for c in np.unique(y):
        idx = rng.permutation(np.where(y == c)[0])
        n = len(idx)
        n_te = max(1, round(n * fr[2])); n_va = max(1, round(n * fr[1]))
        te += list(idx[:n_te]); va += list(idx[n_te:n_te + n_va]); tr += list(idx[n_te + n_va:])
    return np.array(tr), np.array(va), np.array(te)

def augment(xy):
    """Realistic variations of one stroke: trimmed ends, small rotation,
    stretch/shear, wobble. No flips (they could turn one shape into another)."""
    n = len(xy)
    a = int(rng.integers(0, max(1, int(0.04 * n)) + 1))
    b = n - int(rng.integers(0, max(1, int(0.04 * n)) + 1))
    xy = xy[a:b] if b - a > 10 else xy
    p = normalise(resample(xy, NPTS))   # fixed frame, so position is preserved
    th = np.radians(rng.uniform(-10, 10))
    R = np.array([[np.cos(th), -np.sin(th)], [np.sin(th), np.cos(th)]])
    S = np.diag(rng.uniform(0.9, 1.1, 2))
    H = np.array([[1, rng.uniform(-0.1, 0.1)], [0, 1]])
    p = p @ (R @ S @ H).T
    p = p + rng.normal(0, 0.02, p.shape)
    return rasterise(np.clip(p, -1.0, 1.0))

def make_images(strokes, y, idx, per_class=None):
    """Originals always included; if per_class is given, top up with augmented copies."""
    X, Y = [], []
    for i in idx:
        X.append(rasterise(normalise(resample(strokes[i], NPTS)))); Y.append(y[i])
    if per_class:
        for c in np.unique(y[idx]):
            pool = [i for i in idx if y[i] == c]
            have = sum(1 for v in Y if v == c)
            for _ in range(max(0, per_class - have)):
                X.append(augment(strokes[int(rng.choice(pool))])); Y.append(c)
    return np.array(X, np.float32)[:, None], np.array(Y)

# ---------- model + training ----------
def main():
    import torch, torch.nn as nn
    torch.manual_seed(SEED)

    strokes, y, names = load_strokes()
    counts = {n: int((y == i).sum()) for i, n in enumerate(names)}
    print("strokes per class:", counts)
    if min(counts.values()) < 5:
        print("WARNING: a class has fewer than 5 strokes; its test result will be unreliable.")

    tr, va, te = split(y)
    Xtr, ytr = make_images(strokes, y, tr, TARGET_PER_CLASS)
    Xva, yva = make_images(strokes, y, va)          # real strokes only, no augmentation
    Xte, yte = make_images(strokes, y, te)
    print(f"train {len(Xtr)} (augmented), val {len(Xva)}, test {len(Xte)} (real strokes only)")

    # FPGA-friendly: plain conv/ReLU/maxpool/linear, no batch norm
    net = nn.Sequential(
        nn.Conv2d(1, 8, 3, padding=1), nn.ReLU(), nn.MaxPool2d(2),     # IMG/2
        nn.Conv2d(8, 16, 3, padding=1), nn.ReLU(), nn.MaxPool2d(2),    # IMG/4
        nn.Flatten(), nn.Dropout(0.2),
        nn.Linear(16 * (IMG // 4) ** 2, len(names)))
    opt = torch.optim.Adam(net.parameters(), lr=LR)
    lossf = nn.CrossEntropyLoss()
    T = lambda a, dt=torch.float32: torch.tensor(a, dtype=dt)
    Xtr_t, ytr_t, Xva_t, yva_t = T(Xtr), T(ytr, torch.long), T(Xva), T(yva, torch.long)

    best, best_state = -1, None
    for ep in range(EPOCHS):
        net.train()
        perm = torch.randperm(len(Xtr_t))
        for i in range(0, len(perm), BATCH):
            b = perm[i:i + BATCH]
            opt.zero_grad(); lossf(net(Xtr_t[b]), ytr_t[b]).backward(); opt.step()
        net.eval()
        with torch.no_grad():
            acc = (net(Xva_t).argmax(1) == yva_t).float().mean().item()
        if acc >= best:
            best, best_state = acc, {k: v.clone() for k, v in net.state_dict().items()}
        if ep % 10 == 9:
            print(f"epoch {ep+1}: val acc {acc:.3f}")
    net.load_state_dict(best_state); net.eval()

    with torch.no_grad():
        pred = net(T(Xte)).argmax(1).numpy()
    print(f"\nTEST accuracy: {(pred == yte).mean():.3f}  (best val {best:.3f})")
    print("confusion matrix (rows = true, cols = predicted):", names)
    cm = np.zeros((len(names), len(names)), int)
    for t, p in zip(yte, pred): cm[t, p] += 1
    print(cm)

    torch.save(net.state_dict(), 'model.pt')
    np.savez('weights.npz', labels=np.array(names),
             **{k.replace('.', '_'): v.numpy() for k, v in net.state_dict().items()})
    print("saved model.pt and weights.npz")

if __name__ == '__main__':
    main()
