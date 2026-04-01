import argparse
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def load_csv(path: Path) -> pd.DataFrame:
    if not path.exists():
        return pd.DataFrame()
    return pd.read_csv(path)


def mean_throughput(df: pd.DataFrame, group_cols: list[str]) -> pd.DataFrame:
    if df.empty:
        return df
    return (
        df.groupby(group_cols, as_index=False)["throughput_ops_s"]
        .mean()
        .rename(columns={"throughput_ops_s": "throughput_mean"})
    )


def plot_throughput_vs_workers(df: pd.DataFrame, model: str, out_file: Path) -> None:
    filtered = df[df["model"] == model].copy()
    if filtered.empty:
        return

    agg = mean_throughput(filtered, ["architecture", "workers", "model"])
    if agg.empty:
        return

    plt.figure(figsize=(8, 5))
    for arch in sorted(agg["architecture"].unique()):
        part = agg[agg["architecture"] == arch].sort_values("workers")
        plt.plot(part["workers"], part["throughput_mean"], marker="o", label=arch)

    plt.title(f"Throughput vs Workers ({model})")
    plt.xlabel("Workers")
    plt.ylabel("Throughput (ops/s)")
    plt.grid(True, alpha=0.3)
    plt.legend()
    plt.tight_layout()
    plt.savefig(out_file)
    plt.close()


def plot_model_comparison(df: pd.DataFrame, out_file: Path) -> None:
    filtered = df[df["model"].isin(["unnumbered", "numbered"])].copy()
    if filtered.empty:
        return

    agg = mean_throughput(filtered, ["architecture", "model"])
    if agg.empty:
        return

    pivot = agg.pivot(index="model", columns="architecture", values="throughput_mean")
    pivot.plot(kind="bar", figsize=(8, 5))
    plt.title("Unnumbered vs Numbered Throughput")
    plt.xlabel("Model")
    plt.ylabel("Mean throughput (ops/s)")
    plt.grid(True, axis="y", alpha=0.3)
    plt.tight_layout()
    plt.savefig(out_file)
    plt.close()


def plot_hotspot_comparison(df: pd.DataFrame, out_file: Path) -> None:
    if df.empty:
        return

    agg = mean_throughput(df, ["architecture", "workers"])
    if agg.empty:
        return

    plt.figure(figsize=(8, 5))
    for arch in sorted(agg["architecture"].unique()):
        part = agg[agg["architecture"] == arch].sort_values("workers")
        plt.plot(part["workers"], part["throughput_mean"], marker="o", label=arch)

    plt.title("Hotspot 80/5 Throughput vs Workers")
    plt.xlabel("Workers")
    plt.ylabel("Throughput (ops/s)")
    plt.grid(True, alpha=0.3)
    plt.legend()
    plt.tight_layout()
    plt.savefig(out_file)
    plt.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Build report plots from experiment CSV files")
    parser.add_argument("--results-dir", default="results", help="Directory with CSV outputs")
    parser.add_argument("--plots-dir", default="results/plots", help="Output directory for PNG plots")
    args = parser.parse_args()

    results_dir = Path(args.results_dir)
    plots_dir = Path(args.plots_dir)
    ensure_dir(plots_dir)

    direct = load_csv(results_dir / "direct_scaling_results.csv")
    indirect = load_csv(results_dir / "indirect_scaling_results.csv")
    hotspot = load_csv(results_dir / "hotspot_comparison_results.csv")

    combined = pd.concat([direct, indirect], ignore_index=True) if not direct.empty or not indirect.empty else pd.DataFrame()

    plot_throughput_vs_workers(combined, "unnumbered", plots_dir / "throughput_vs_workers_unnumbered.png")
    plot_throughput_vs_workers(combined, "numbered", plots_dir / "throughput_vs_workers_numbered.png")
    plot_model_comparison(combined, plots_dir / "model_comparison.png")
    plot_hotspot_comparison(hotspot, plots_dir / "hotspot_80_5_comparison.png")

    print("Plots generated in", plots_dir)


if __name__ == "__main__":
    main()
