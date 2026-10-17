param(
	[string]$Source = "$PSScriptRoot/../assets/map/milkTea/shop_interior_reference.png",
	[string]$Output = "$PSScriptRoot/../assets/map/milk_tea_layers"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Collections.Generic;
using System.IO;

public static class MilkTeaLayers {
    const int W = 1376, H = 768;
    static byte[] labels = new byte[W * H];
    static bool[] wallGeometry = new bool[W * H];
    static Bitmap source;

    static void Rect(int x, int y, int width, int height, byte label) {
        for (int py = y; py < y + height; py++)
            for (int px = x; px < x + width; px++) {
                labels[py * W + px] = label;
                if (label == 2) wallGeometry[py * W + px] = true;
            }
    }
    static void Polygon(byte label, params int[] xy) {
        for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) {
            bool inside = false;
            for (int i = 0, j = xy.Length - 2; i < xy.Length; j = i, i += 2) {
                double xi = xy[i], yi = xy[i + 1], xj = xy[j], yj = xy[j + 1];
                if ((yi > y + .5) != (yj > y + .5) &&
                    x + .5 < (xj - xi) * (y + .5 - yi) / (yj - yi) + xi)
                    inside = !inside;
            }
            if (inside && !(label == 3 && wallGeometry[y * W + x])) labels[y * W + x] = label;
        }
    }
    static bool IsWallBackground(Color c) {
        return c.R >= 195 && c.G >= 190 && c.B >= 150 &&
            c.R >= c.G - 2 && c.R - c.G < 22 && c.G - c.B >= 20 && c.G - c.B < 45;
    }
    // Remove wall-colored pixels connected to each object bounding box edge.
    // Enclosed cream pixels (cups, pillows, appliance faces) remain objects.
    static void Object(int x, int y, int width, int height) {
        bool[] background = new bool[width * height];
        Queue<int> queue = new Queue<int>();
        Action<int,int> visit = (px,py) => {
            if (px < 0 || py < 0 || px >= width || py >= height) return;
            int i = py * width + px;
            if (!background[i] && IsWallBackground(source.GetPixel(x + px, y + py))) {
                background[i] = true; queue.Enqueue(i);
            }
        };
        for (int px = 0; px < width; px++) { visit(px,0); visit(px,height-1); }
        for (int py = 0; py < height; py++) { visit(0,py); visit(width-1,py); }
        while (queue.Count > 0) {
            int i = queue.Dequeue(), px = i % width, py = i / width;
            visit(px-1,py); visit(px+1,py); visit(px,py-1); visit(px,py+1);
        }
        for (int py = 0; py < height; py++) for (int px = 0; px < width; px++) {
            int i = (y + py) * W + x + px;
            if (!background[py * width + px] && labels[i] == 2) labels[i] = 1;
        }
    }
    static Color HiddenWall(int x, int y) {
        // Use continuous rows from unobstructed wall faces, rather than nearby
        // object highlights, so inpainting does not leave appliance silhouettes.
        if (y >= 449 && x < 335) return source.GetPixel(286,Math.Min(y,547));
        if (y >= 375 && x >= 550 && x < 655) return source.GetPixel(608,400);
        if (x < 398) return source.GetPixel(191,Math.Max(104,Math.Min(y,180)));
        if (x < 650) return source.GetPixel(744,Math.Max(104,Math.Min(y,188)));
        return source.GetPixel(744,Math.Max(104,Math.Min(y,205)));
    }
    static Color HiddenFloor(int x, int y) {
        if (x < 340 && y >= 508)
            return x < 332 ? source.GetPixel(283 + (x % 12), y) : source.GetPixel(350, y);
        if (x >= 1077 && y >= 592)
            return source.GetPixel(1037 + (x % 23), 520 + (y % 23));
        return source.GetPixel(475 + (x % 60), y);
    }
    static void SmoothHiddenWall(Bitmap walls) {
        var cells = new List<int>();
        var valid = new bool[W*H];
        var red = new double[W*H]; var green = new double[W*H]; var blue = new double[W*H];
        for (int i=0; i<W*H; i++) {
            if (!wallGeometry[i]) continue;
            Color c=walls.GetPixel(i%W,i/W);
            if (!IsWallBackground(c)) continue;
            valid[i]=true; red[i]=c.R; green[i]=c.G; blue[i]=c.B;
            if (labels[i]!=2) cells.Add(i);
        }
        for (int iteration=0; iteration<450; iteration++) foreach (int i in cells) {
            double r=0,g=0,b=0; int count=0;
            foreach (int j in new int[]{i-1,i+1,i-W,i+W}) {
                if (j<0 || j>=W*H || !valid[j]) continue;
                r+=red[j]; g+=green[j]; b+=blue[j]; count++;
            }
            if (count>0) { red[i]=r/count; green[i]=g/count; blue[i]=b/count; }
        }
        foreach (int i in cells) walls.SetPixel(i%W,i/W,
            Color.FromArgb(255,(int)Math.Round(red[i]),(int)Math.Round(green[i]),(int)Math.Round(blue[i])));
    }
    static void RetainObjectFringes() {
        for (int pass=0; pass<2; pass++) {
            var fringe=new List<int>();
            for (int i=W+1; i<W*(H-1)-1; i++) {
                if (!wallGeometry[i] || labels[i]!=2 || !IsWallBackground(source.GetPixel(i%W,i/W))) continue;
                foreach (int j in new int[]{i-1,i+1,i-W,i+W})
                    if (wallGeometry[j] && labels[j]==1) { fringe.Add(i); break; }
            }
            foreach (int i in fringe) labels[i]=1;
        }
    }
    public static void Run(string input, string output) {
        source = new Bitmap(input);
        if (source.Width != W || source.Height != H) throw new Exception("Unexpected reference size");
        Directory.CreateDirectory(output);
        Polygon(1, 115,57, 118,55, 1258,55, 1261,58, 1261,708, 1168,708,
            1168,755, 1082,755, 1082,708, 115,708);

        // Fixed architectural walls, measured in the original source canvas.
        Rect(115,55,1146,47,2);
        Rect(115,102,36,606,2); Rect(1227,102,34,606,2);
        Rect(151,663,927,45,2); Rect(1168,663,59,45,2);
        Rect(150,102,246,89,2); Rect(432,102,186,88,2);
        Rect(653,102,574,109,2);
        Rect(395,81,37,260,2); Rect(396,341,37,114,2);
        Rect(618,81,35,297,2); Rect(560,341,58,38,2);
        Rect(560,379,61,77,2); Rect(621,379,32,123,2);
        Rect(139,411,185,27,2); Rect(299,431,36,81,2);
        Rect(139,431,160,18,2); Rect(150,449,149,99,2);
        Rect(299,511,23,102,2);
        Rect(612,560,37,119,2); Rect(620,457,17,103,2);

        // Objects overlapping wall faces keep their original outlines and pixels.
        Object(152,180,80,167); Object(243,151,48,74);
        Object(229,187,92,77); Object(321,123,75,139);
        Object(432,103,186,50); Object(437,133,106,151);
        Object(549,152,68,142); Object(663,103,23,102);
        Object(695,188,29,30); Object(773,151,136,65);
        Object(767,188,149,30);
        Object(921,189,81,70); Object(1013,169,59,77);
        Object(1100,101,103,89); Object(1109,191,82,45);
        Object(153,458,49,84); Object(204,485,28,32);
        Rect(235,459,43,49,1); Object(231,511,51,68);
        Object(563,455,46,64);
        RetainObjectFringes();

        // Architectural door leaves and their own frames, never cabinet doors.
        Polygon(3, 322,362, 383,334, 395,334, 395,452, 334,475, 322,469);
        Rect(433,341,36,114,3);
        Rect(322,524,12,140,3);
        Polygon(3, 653,419, 732,419, 732,501, 729,501, 729,489, 660,489, 660,501, 653,501);
        Rect(1077,592,92,119,3);
        // Glazing exposes the existing floor; it is not an opaque door panel.
        Rect(1090,613,65,38,1);
        Rect(1090,692,65,14,1);

        // Exclude the tan backdrop around the outside doormat.
        for (int y=711; y<755; y++) for (int x=1082; x<1168; x++) {
            Color c=source.GetPixel(x,y);
            if (c.R > c.G+5 && c.G > c.B+5) labels[y*W+x]=0;
        }

        Bitmap floor = new Bitmap(W,H,PixelFormat.Format32bppArgb);
        Bitmap walls = new Bitmap(W,H,PixelFormat.Format32bppArgb);
        Bitmap doors = new Bitmap(W,H,PixelFormat.Format32bppArgb);
        Bitmap preview = new Bitmap(W,H,PixelFormat.Format32bppArgb);
        int exact = 0, mismatched = 0, exterior = 0;
        for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) {
            int i = y * W + x; byte layer = labels[i];
            Color original = source.GetPixel(x,y);
            if (layer == 0) { exterior++; continue; }
            if (wallGeometry[i]) {
                if (layer == 2) walls.SetPixel(x,y,original);
                else if (layer == 1) walls.SetPixel(x,y,HiddenWall(x,y));
            }
            if (layer == 1) floor.SetPixel(x,y,original);
            if (layer == 3) {
                if (!wallGeometry[i]) floor.SetPixel(x,y,HiddenFloor(x,y));
                else walls.SetPixel(x,y,HiddenWall(x,y));
                doors.SetPixel(x,y,original);
            }
            Color composite = doors.GetPixel(x,y);
            if (composite.A == 0) composite = floor.GetPixel(x,y);
            if (composite.A == 0) composite = walls.GetPixel(x,y);
            preview.SetPixel(x,y,composite);
            if (composite.ToArgb() == original.ToArgb()) exact++; else mismatched++;
        }
        if (mismatched != 0) throw new Exception("Visible pixel reconstruction mismatch: " + mismatched);
        SmoothHiddenWall(walls);
        floor.Save(Path.Combine(output,"floor.png"),ImageFormat.Png);
        walls.Save(Path.Combine(output,"walls.png"),ImageFormat.Png);
        doors.Save(Path.Combine(output,"doors.png"),ImageFormat.Png);
        preview.Save(Path.Combine(output,"composite_preview.png"),ImageFormat.Png);
        File.WriteAllText(Path.Combine(output,"validation.json"),
            "{\n  \"canvas\": [1376, 768],\n  \"stack_bottom_to_top\": [\"walls\", \"floor\", \"doors\"],\n" +
            "  \"visible_source_pixels_preserved\": " + exact + ",\n  \"visible_pixel_mismatches\": " + mismatched + ",\n" +
            "  \"transparent_exterior_pixels\": " + exterior + "\n}\n");
        Console.WriteLine("Reconstructed visible source pixels: " + exact + "; mismatches: " + mismatched);
        source.Dispose(); floor.Dispose(); walls.Dispose(); doors.Dispose(); preview.Dispose();
    }
}
'@ -ReferencedAssemblies System.Drawing

[MilkTeaLayers]::Run([IO.Path]::GetFullPath($Source), [IO.Path]::GetFullPath($Output))
