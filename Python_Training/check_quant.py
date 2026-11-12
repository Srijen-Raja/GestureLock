"""Measure value ranges and simulate 8-bit quantisation of the trained CNN.
Needs: weights.npz, strokes.csv, make_dataset.py, train_cnn.py (numpy/pandas only, no torch).
"""
import numpy as np
from train_cnn import load_strokes, make_images

W = np.load('weights.npz')
w1, b1, w2, b2, w3, b3 = (W[k] for k in ('0_weight', '0_bias', '3_weight', '3_bias', '8_weight', '8_bias'))

def conv(x, w, b):                       # x: (C,H,W), 3x3, padding 1
    xp = np.pad(x, ((0, 0), (1, 1), (1, 1)))
    win = np.lib.stride_tricks.sliding_window_view(xp, (3, 3), axis=(1, 2))
    return np.einsum('chwij,ocij->ohw', win, w) + b[:, None, None]

def pool(x):
    c, h, wd = x.shape
    return x.reshape(c, h // 2, 2, wd // 2, 2).max(axis=(2, 4))

def forward(img, q=None):
    """q = None: float. q = dict of activation scales: weights and activations 8-bit."""
    f = (lambda w: np.round(w / (np.abs(w).max() / 127)) * (np.abs(w).max() / 127)) if q else (lambda w: w)
    a1 = pool(np.maximum(conv(img, f(w1), b1), 0))
    if q: a1 = np.clip(np.round(a1 / q['a1']), 0, 255) * q['a1']
    a2 = pool(np.maximum(conv(a1, f(w2), b2), 0))
    if q: a2 = np.clip(np.round(a2 / q['a2']), 0, 255) * q['a2']
    return f(w3) @ a2.reshape(-1) + b3, (a1, a2)

strokes, y, names = load_strokes()
X, Y = make_images(strokes, y, np.arange(len(y)))        # real strokes only
outs = [forward(x) for x in X]
a1max = max(o[1][0].max() for o in outs); a2max = max(o[1][1].max() for o in outs)
logits = np.array([o[0] for o in outs])
print("classes:", names)
print(f"weights   conv1 [{w1.min():.2f},{w1.max():.2f}]  conv2 [{w2.min():.2f},{w2.max():.2f}]  fc [{w3.min():.2f},{w3.max():.2f}]")
print(f"biases    [{min(b1.min(), b2.min(), b3.min()):.2f},{max(b1.max(), b2.max(), b3.max()):.2f}]")
print(f"activations after layer 1 max {a1max:.2f}, after layer 2 max {a2max:.2f}, logits [{logits.min():.2f},{logits.max():.2f}]")

q = {'a1': a1max / 255, 'a2': a2max / 255}
pf = logits.argmax(1)
pq = np.array([forward(x, q)[0].argmax() for x in X])
print(f"\nfloat accuracy on all strokes: {(pf == Y).mean():.3f}")
print(f"8-bit accuracy on all strokes: {(pq == Y).mean():.3f}")
print(f"8-bit agrees with float on {(pf == pq).mean() * 100:.1f}% of strokes")
