"""Single-layer (softmax regression) classifier on the stroke image, at several resolutions.
Same strokes, split and augmentation as train_cnn.py. Needs numpy + pandas only.
Usage: python train_linear.py          (in the RC folder, next to strokes.csv, make_dataset.py, train_cnn.py)
"""
import numpy as np
import make_dataset as MD
import train_cnn as T

RESOLUTIONS = [16, 32, 64]
EPOCHS, LR, L2 = 300, 0.02, 1e-4

def train(Xtr, ytr, C):
    n, d = Xtr.shape
    W = np.zeros((d, C), np.float32); b = np.zeros(C, np.float32)
    mW, vW, mb, vb = np.zeros_like(W), np.zeros_like(W), np.zeros_like(b), np.zeros_like(b)
    Y = np.eye(C, dtype=np.float32)[ytr]
    for t in range(1, EPOCHS + 1):                       # full-batch Adam
        z = Xtr @ W + b; z -= z.max(1, keepdims=True)
        p = np.exp(z); p /= p.sum(1, keepdims=True)
        gW = Xtr.T @ (p - Y) / n + L2 * W; gb = (p - Y).mean(0)
        for g, m, v, w in ((gW, mW, vW, W), (gb, mb, vb, b)):
            m *= 0.9; m += 0.1 * g; v *= 0.999; v += 0.001 * g * g
            w -= LR * (m / (1 - 0.9 ** t)) / (np.sqrt(v / (1 - 0.999 ** t)) + 1e-8)
    return W, b

def int8_scores(X, W, b):
    s = np.abs(W).max() / 127
    return X @ (np.round(W / s)) + np.round(b / s)       # inputs are 0/1, so no input scale

def main():
    strokes, y, names = T.load_strokes(); C = len(names)
    print("classes:", names)
    for res in RESOLUTIONS:
        MD.IMG = res                                     # rasterise() reads this global
        T.rng = np.random.default_rng(T.SEED)            # identical split for every resolution
        tr, va, te = T.split(y)
        Xtr, ytr = T.make_images(strokes, y, tr, T.TARGET_PER_CLASS)
        Xte, yte = T.make_images(strokes, y, te)
        Xtr = Xtr.reshape(len(Xtr), -1); Xte = Xte.reshape(len(Xte), -1)
        W, b = train(Xtr, ytr, C)
        acc = np.mean((Xte @ W + b).argmax(1) == yte)
        acc8 = np.mean(int8_scores(Xte, W, b).argmax(1) == yte)
        cm = np.zeros((C, C), int)
        for t, p in zip(yte, (Xte @ W + b).argmax(1)): cm[t, p] += 1
        print(f"\n{res}x{res}: weights {W.size}, MACs {W.size}, test accuracy {acc:.3f} (int8 weights {acc8:.3f}) on {len(yte)} strokes")
        print(cm)
    print("\nCompare with the CNN test accuracy from train_cnn.py (same split).")

if __name__ == '__main__':
    main()
