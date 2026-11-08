# Makes assets/images/market_farmer_dark.png from market_farmer.png: the
# Market welcome banner's cream curve turned forest green (#193D2A) for
# Dark Mode, the rest of the picture untouched. Run again if the banner
# picture is replaced (Windows PowerShell, System.Drawing):
#   powershell -NoProfile -File tool/market_banner_dark.ps1 -src assets/images/market_farmer.png -dst assets/images/market_farmer_dark.png
param([string]$src, [string]$dst)
Add-Type -AssemblyName System.Drawing
$code = @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class Recolor5 {
  // The cream curve: bright and warm. The sky and its haze are cooler or
  // duller; leaf highlights are much greener.
  static bool Cream(int r, int g, int b) {
    return r >= 241 && g >= 241 && b >= 220 && (r - b) >= 3 && (r - b) <= 30;
  }

  // Near the left edge the faint leaf and the pale strip beside the curve
  // join it too, so no light patch is left there.
  static bool Pale(int r, int g, int b) {
    return r >= 224 && g >= 230 && b >= 205 && (g - b) <= 30;
  }

  public static void Run(string src, string dst) {
    var bmp = new Bitmap(src);
    int w = bmp.Width, h = bmp.Height;
    var rect = new Rectangle(0, 0, w, h);
    var data = bmp.LockBits(rect, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
    int stride = data.Stride;
    byte[] px = new byte[stride * h];
    Marshal.Copy(data.Scan0, px, 0, px.Length);

    // The curve lies in the left part of the picture.
    const int maxX = 560;
    double[] mask = new double[w * h];
    // Only what joins the curve (from inside it): no speck of the haze.
    var q = new System.Collections.Generic.Queue<int>();
    int seed = 140 * w + 200;
    mask[seed] = 1; q.Enqueue(seed);
    while (q.Count > 0) {
      int i = q.Dequeue();
      int x = i % w, y = i / w;
      for (int k = 0; k < 4; k++) {
        int xx = x + (k == 0 ? -1 : k == 1 ? 1 : 0);
        int yy = y + (k == 2 ? -1 : k == 3 ? 1 : 0);
        if (xx < 0 || yy < 0 || xx >= maxX || yy >= h) continue;
        int j = yy * w + xx;
        if (mask[j] == 1) continue;
        int o = yy * stride + xx * 4;
        if (px[o + 3] < 250) continue;
        int r = px[o + 2], g = px[o + 1], b = px[o];
        if (!(Cream(r, g, b) || (xx < 120 && yy >= 32 && Pale(r, g, b)))) continue;
        mask[j] = 1; q.Enqueue(j);
      }
    }
    // A soft edge: the mask blurred over 5 x 5.
    double[] soft = new double[w * h];
    for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) {
      double sum = 0; int n = 0;
      for (int dy = -2; dy <= 2; dy++) for (int dx = -2; dx <= 2; dx++) {
        int xx = x + dx, yy = y + dy;
        if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
        sum += mask[yy * w + xx]; n++;
      }
      soft[y * w + x] = sum / n;
    }

    // #193D2A, and the cream it replaces.
    const int tr = 0x19, tg = 0x3D, tb = 0x2A;
    const int cr = 253, cg = 250, cb = 243;
    for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) {
      int i = y * w + x; int o = y * stride + x * 4;
      double m = soft[i];
      if (m <= 0 || px[o + 3] == 0) continue;
      int r = px[o + 2], g = px[o + 1], b = px[o];
      // The faint leaves on the curve (a little darker than the cream)
      // stay as a slightly lighter green.
      double d = ((cr - r) + (cg - g) + (cb - b)) / 3.0;
      if (d < 0) d = 0;
      if (d > 12) d = 12;
      double nr = Math.Min(255, tr + d * 0.55);
      double ng = Math.Min(255, tg + d * 1.25);
      double nb = Math.Min(255, tb + d * 0.45);
      // On the curve itself, all of it; at its edge, as much as the pixel
      // is part of it, and never on the dark leaves beside it.
      double wgt = m;
      if (mask[i] == 0) {
        double lum = 0.299 * r + 0.587 * g + 0.114 * b;
        double bright = (lum - 110.0) / (225.0 - 110.0);
        if (bright < 0) bright = 0;
        if (bright > 1) bright = 1;
        wgt = Math.Min(1.0, m * 2.2) * bright;
      }
      px[o + 2] = (byte)(r * (1 - wgt) + nr * wgt);
      px[o + 1] = (byte)(g * (1 - wgt) + ng * wgt);
      px[o]     = (byte)(b * (1 - wgt) + nb * wgt);
    }
    Marshal.Copy(px, 0, data.Scan0, px.Length);
    bmp.UnlockBits(data);
    bmp.Save(dst, ImageFormat.Png);
    bmp.Dispose();
    Console.WriteLine("done");
  }
}
"@
Add-Type -TypeDefinition $code -ReferencedAssemblies System.Drawing
[Recolor5]::Run($src, $dst)
