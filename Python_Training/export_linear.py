"""Train the 16x16 single-layer classifier and export its weights.
Run in the RC folder (next to strokes.csv, make_dataset.py, train_cnn.py, train_linear.py):
    python export_linear.py
Writes the folder  export_linear/ :
  linear_w.mem        int8 weights for Vivado ($readmemh): one value per line, 2 hex digits (two's complement)
                      line number = class*256 + pixel,  pixel = row*16 + column
  linear_b.mem        int32 biases for Vivado, one per line, 8 hex digits, one line per class
  linear_params.txt   class order, int8 scale, layout, accuracy
  linear_weights.csv  the 7x256 int8 matrix: one row per class, columns p0..p255, last column = bias
Uses the same split, augmentation and training as train_linear.py (16x16), so the weights match that run.
"""
import os
import numpy as np
import make_dataset as MD
import train_cnn as T
from train_linear import train

RES, OUT = 16, 'export_linear'
os.makedirs(OUT, exist_ok=True)

strokes, y, names = T.load_strokes(); C = len(names)
MD.IMG = RES
T.rng = np.random.default_rng(T.SEED)          # same split as train_linear.py
tr, va, te = T.split(y)
Xtr, ytr = T.make_images(strokes, y, tr, T.TARGET_PER_CLASS)
Xte, yte = T.make_images(strokes, y, te)
Xtr = Xtr.reshape(len(Xtr), -1); Xte = Xte.reshape(len(Xte), -1)
W, b = train(Xtr, ytr, C)                      # W: (256, C) float, b: (C,)

# ---- int8 quantisation (inputs are 0/1, so only the weights need a scale) ----
s = float(np.abs(W).max() / 127)
Wq = np.clip(np.round(W / s), -127, 127).astype(np.int64).T      # (C, 256), row = class
bq = np.round(b / s).astype(np.int64)                            # bias in the same units
acc_f = np.mean((Xte @ W + b).argmax(1) == yte)
acc_q = np.mean((Xte @ Wq.T + bq).argmax(1) == yte)

hx = lambda v, bits: format(int(v) & ((1 << bits) - 1), '0%dx' % (bits // 4))
open(f'{OUT}/linear_w.mem', 'w').write('\n'.join(hx(v, 8) for v in Wq.reshape(-1)) + '\n')
open(f'{OUT}/linear_b.mem', 'w').write('\n'.join(hx(v, 32) for v in bq) + '\n')
with open(f'{OUT}/linear_weights.csv', 'w') as f:
    f.write('class,' + ','.join(f'p{i}' for i in range(256)) + ',bias\n')
    for c in range(C):
        f.write(names[c] + ',' + ','.join(str(int(v)) for v in Wq[c]) + f',{int(bq[c])}\n')

# ---- read the .mem files back and check they reproduce the same predictions ----
rd = lambda fn, bits: np.array([(lambda a: a - (1 << bits) if a >= 1 << (bits - 1) else a)(int(t, 16))
                                for t in open(fn).read().split()], np.int64)
W2 = rd(f'{OUT}/linear_w.mem', 8).reshape(C, 256); b2 = rd(f'{OUT}/linear_b.mem', 32)
assert (W2 == Wq).all() and (b2 == bq).all(), "round-trip mismatch"
acc_m = np.mean((Xte @ W2.T + b2).argmax(1) == yte)

info = [f"classes (row / output index -> name): {dict(enumerate(names))}",
        f"image: {RES}x{RES}, pixel index = row*16 + column (row 0 = top, joystick up = image up), pixel = 1 when the stroke touches it",
        f"scores = sum over lit pixels of weight[class][pixel] + bias[class]; predicted class = argmax (first one on a tie)",
        f"float weight ~= int8 value * {s:.6f}",
        f"int8 range used: [{Wq.min()}, {Wq.max()}], biases [{bq.min()}, {bq.max()}]",
        f"largest possible |score| for a 256 pixel image: {int(np.abs(Wq).sum(1).max() + np.abs(bq).max())} (fits in {int(np.abs(Wq).sum(1).max() + np.abs(bq).max()).bit_length() + 1} bits signed)",
        f"test accuracy on {len(yte)} real strokes: float {acc_f:.3f}, int8 {acc_q:.3f}, from the .mem files {acc_m:.3f}"]
open(f'{OUT}/linear_params.txt', 'w').write('\n'.join(info) + '\n')
print('\n'.join(info)); print(f"\nfiles written to {OUT}/")
