/// Minimal dense linear algebra used by the colour-calibration solver.
///
/// Deliberately small and dependency-free: the calibration problem is at most
/// a 4x4 normal-equation system, so a general matrix library would be far more
/// weight than the task needs (master spec section 6).
library;

import 'dart:math' as math;

class LinearAlgebra {
  const LinearAlgebra._();

  /// Solves `A x = b` for a square matrix `A` using Gaussian elimination with
  /// partial pivoting.
  ///
  /// Returns null when the system is singular or ill-conditioned, which the
  /// caller must treat as calibration failure rather than substituting a
  /// fallback transform.
  static List<double>? solve(List<List<double>> a, List<double> b) {
    final int n = b.length;
    if (a.length != n) return null;
    for (final List<double> row in a) {
      if (row.length != n) return null;
    }

    // Work on copies; callers reuse their matrices.
    final List<List<double>> m =
        List<List<double>>.generate(n, (int i) => List<double>.of(a[i]));
    final List<double> rhs = List<double>.of(b);

    for (int col = 0; col < n; col++) {
      // Partial pivot: pick the row with the largest magnitude in this column.
      int pivot = col;
      double best = m[col][col].abs();
      for (int row = col + 1; row < n; row++) {
        final double candidate = m[row][col].abs();
        if (candidate > best) {
          best = candidate;
          pivot = row;
        }
      }
      if (best < 1e-12) return null; // Singular.

      if (pivot != col) {
        final List<double> tmpRow = m[col];
        m[col] = m[pivot];
        m[pivot] = tmpRow;
        final double tmpVal = rhs[col];
        rhs[col] = rhs[pivot];
        rhs[pivot] = tmpVal;
      }

      final double diag = m[col][col];
      for (int row = col + 1; row < n; row++) {
        final double factor = m[row][col] / diag;
        if (factor == 0) continue;
        for (int k = col; k < n; k++) {
          m[row][k] -= factor * m[col][k];
        }
        rhs[row] -= factor * rhs[col];
      }
    }

    // Back substitution.
    final List<double> x = List<double>.filled(n, 0);
    for (int row = n - 1; row >= 0; row--) {
      double sum = rhs[row];
      for (int k = row + 1; k < n; k++) {
        sum -= m[row][k] * x[k];
      }
      x[row] = sum / m[row][row];
    }

    for (final double v in x) {
      if (v.isNaN || v.isInfinite) return null;
    }
    return x;
  }

  /// Least-squares solution of an over-determined system `design * x ~= y`
  /// via the normal equations `(D^T D) x = D^T y`.
  ///
  /// Adequate here because the design matrix is tiny and well-scaled (linear
  /// RGB in [0, 1] plus a bias term). Returns null if the normal equations are
  /// singular, e.g. when the reference patches are degenerate.
  static List<double>? leastSquares(
    List<List<double>> design,
    List<double> y,
  ) {
    if (design.isEmpty || design.length != y.length) return null;
    final int cols = design.first.length;
    if (design.length < cols) return null; // Under-determined.

    final List<List<double>> ata = List<List<double>>.generate(
      cols,
      (_) => List<double>.filled(cols, 0),
    );
    final List<double> atb = List<double>.filled(cols, 0);

    for (int row = 0; row < design.length; row++) {
      final List<double> d = design[row];
      if (d.length != cols) return null;
      for (int i = 0; i < cols; i++) {
        atb[i] += d[i] * y[row];
        for (int j = 0; j < cols; j++) {
          ata[i][j] += d[i] * d[j];
        }
      }
    }

    // Small Tikhonov term. Without it a reference card photographed under a
    // strong colour cast can produce a near-singular system and a wild
    // transform; the caller would then see a plausible-looking matrix with
    // terrible residuals. Regularising keeps the failure mode honest.
    const double ridge = 1e-8;
    for (int i = 0; i < cols; i++) {
      ata[i][i] += ridge;
    }

    return solve(ata, atb);
  }

  /// Root-mean-square of a list of values.
  static double rms(List<double> values) {
    if (values.isEmpty) return 0;
    double sum = 0;
    for (final double v in values) {
      sum += v * v;
    }
    return math.sqrt(sum / values.length);
  }

  /// Arithmetic mean.
  static double mean(List<double> values) {
    if (values.isEmpty) return 0;
    double sum = 0;
    for (final double v in values) {
      sum += v;
    }
    return sum / values.length;
  }

  /// Sample standard deviation (N-1 denominator). Returns 0 for n < 2.
  static double stdDev(List<double> values) {
    if (values.length < 2) return 0;
    final double m = mean(values);
    double acc = 0;
    for (final double v in values) {
      final double d = v - m;
      acc += d * d;
    }
    return math.sqrt(acc / (values.length - 1));
  }

  /// Linear-interpolated percentile of an unsorted list. `p` is in [0, 1].
  static double percentile(List<double> values, double p) {
    if (values.isEmpty) return 0;
    final List<double> sorted = List<double>.of(values)..sort();
    if (sorted.length == 1) return sorted.first;
    final double pos = (sorted.length - 1) * p.clamp(0.0, 1.0);
    final int lo = pos.floor();
    final int hi = pos.ceil();
    if (lo == hi) return sorted[lo];
    return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
  }
}
