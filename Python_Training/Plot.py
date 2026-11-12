import matplotlib.pyplot as plt
import pandas as pd

# 1. Read dataset from the same directory
df = pd.read_csv("jstk2_dataset.csv")

# 2. Calculate relative offsets with (512, 512) as the origin (0, 0)
df["X_rel"] = df["X_Axis"] - 512
df["Y_rel"] = df["Y_Axis"] - 512

# 3. Initialize side-by-side plots
fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 6))

# Subplot 1: Absolute Raw Coordinates with (512, 512) origin lines
sc1 = ax1.scatter(
    df["X_Axis"], df["Y_Axis"], c=df.index, cmap="viridis", alpha=0.6, s=20
)
ax1.axhline(512, color="red", linestyle="--", linewidth=1.2, label="Y = 512 Axis")
ax1.axvline(512, color="red", linestyle="--", linewidth=1.2, label="X = 512 Axis")
ax1.scatter(
    [512], [512], color="red", s=100, zorder=5, marker="X", label="Origin (512, 512)"
)
ax1.set_title("Absolute Raw Coordinates", fontsize=12)
ax1.set_xlabel("X Axis", fontsize=11)
ax1.set_ylabel("Y Axis", fontsize=11)
ax1.grid(True, linestyle=":", alpha=0.6)
ax1.legend(loc="upper right", fontsize=9)
ax1.set_aspect("equal", adjustable="box")

# Subplot 2: Relative Coordinates shifted to Origin (0, 0)
sc2 = ax2.scatter(
    df["X_rel"], df["Y_rel"], c=df.index, cmap="viridis", alpha=0.6, s=20
)
ax2.axhline(0, color="red", linestyle="--", linewidth=1.2, label="Y = 0 Axis")
ax2.axvline(0, color="red", linestyle="--", linewidth=1.2, label="X = 0 Axis")
ax2.scatter(
    [0], [0], color="red", s=100, zorder=5, marker="X", label="Origin (0, 0)"
)
ax2.set_title("Relative Offsets (Origin at 0, 0)", fontsize=12)
ax2.set_xlabel("ΔX (X_Axis - 512)", fontsize=11)
ax2.set_ylabel("ΔY (Y_Axis - 512)", fontsize=11)
ax2.grid(True, linestyle=":", alpha=0.6)
ax2.legend(loc="upper right", fontsize=9)
ax2.set_aspect("equal", adjustable="box")

# Colorbar for time sequence progression
cbar = fig.colorbar(
    sc2,
    ax=[ax1, ax2],
    label="Time Progression (Sample Index)",
    orientation="vertical",
    shrink=0.8,
)

plt.suptitle("JSTK2 Joystick Coordinate Plot", fontsize=14, y=0.98)
plt.tight_layout()

# Save image and render plot
plt.savefig("jstk2_plot.png", dpi=300, bbox_inches="tight")
plt.show()