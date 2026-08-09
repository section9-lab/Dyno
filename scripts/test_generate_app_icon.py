import unittest
from pathlib import Path

from PIL import Image


ICON_PATH = (
    Path(__file__).resolve().parents[1]
    / "PiWork/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png"
)


class AppIconTests(unittest.TestCase):
    def test_blue_dot_has_optical_gap_above_i_stem(self):
        image = Image.open(ICON_PATH).convert("RGBA")
        blue_pixels = []

        for y in range(image.height):
            for x in range(image.width):
                red, green, blue, alpha = image.getpixel((x, y))
                if alpha > 200 and blue > 180 and blue > red * 1.5 and blue > green * 1.15:
                    blue_pixels.append((x, y))

        self.assertTrue(blue_pixels)
        dot_left = min(x for x, _ in blue_pixels)
        dot_right = max(x for x, _ in blue_pixels)
        dot_bottom = max(y for _, y in blue_pixels)
        probe_left = dot_left + (dot_right - dot_left) // 4
        probe_right = dot_right - (dot_right - dot_left) // 4

        stem_top = next(
            y
            for y in range(dot_bottom + 1, image.height)
            if any(
                max(image.getpixel((x, y))[:3]) < 140
                and image.getpixel((x, y))[3] > 200
                for x in range(probe_left, probe_right + 1)
            )
        )
        gap_ratio = (stem_top - dot_bottom - 1) / image.height

        self.assertGreaterEqual(gap_ratio, 0.027)
        self.assertLessEqual(gap_ratio, 0.033)


if __name__ == "__main__":
    unittest.main()
