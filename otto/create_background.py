#!/usr/bin/env python3
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

# DMG background dimensions
WIDTH, HEIGHT = 600, 400

# UI colors (modern purple gradient with lighter accent)
PRIMARY_COLOR = (88, 86, 214)  # Main purple
SECONDARY_COLOR = (120, 94, 240)  # Lighter purple
ACCENT_COLOR = (255, 255, 255)  # White text/elements


def create_gradient_background(width, height, color1, color2):
    """Create a smooth gradient background"""
    background = Image.new("RGBA", (width, height), color=(0, 0, 0, 0))
    draw = ImageDraw.Draw(background)

    for y in range(height):
        # Calculate gradient color at this position
        r = int(color1[0] + (color2[0] - color1[0]) * y / height)
        g = int(color1[1] + (color2[1] - color1[1]) * y / height)
        b = int(color1[2] + (color2[2] - color1[2]) * y / height)

        draw.line([(0, y), (width, y)], fill=(r, g, b, 255))

    return background


def add_text(image, text, position, font_size=40, color=(255, 255, 255, 255)):
    """Add text to the image"""
    draw = ImageDraw.Draw(image)
    # Try to use a nice font if available, otherwise use default
    try:
        font = ImageFont.truetype("Arial.ttf", font_size)
    except IOError:
        try:
            font = ImageFont.truetype(
                "/System/Library/Fonts/SFNSDisplay.ttf", font_size
            )
        except IOError:
            font = ImageFont.load_default()

    draw.text(position, text, font=font, fill=color)
    return image


def add_instructions(image):
    """Add installation instructions to the image"""
    instructions = ["Drag Otto to Applications", "to install"]

    y_position = 280
    for instruction in instructions:
        image = add_text(image, instruction, (180, y_position), font_size=24)
        y_position += 30

    return image


def add_circles(image):
    """Add decorative circles to the background"""
    draw = ImageDraw.Draw(image)

    # Add some decorative circles with transparency
    for x, y, size in [(50, 50, 100), (500, 300, 80), (400, 80, 60)]:
        for i in range(size, 0, -20):
            alpha = int(100 * (i / size))
            draw.ellipse(
                (x - i / 2, y - i / 2, x + i / 2, y + i / 2),
                outline=(255, 255, 255, alpha),
                width=2,
            )

    return image


def add_logo(image, position=(250, 120)):
    """Add a simple logo placeholder"""
    draw = ImageDraw.Draw(image)

    # Create a simple circular logo
    logo_size = 80
    x, y = position
    draw.ellipse(
        (x - logo_size, y - logo_size, x + logo_size, y + logo_size),
        fill=(255, 255, 255, 80),
        outline=(255, 255, 255, 200),
        width=3,
    )

    # Add an "O" in the middle for Otto
    image = add_text(
        image, "O", (x - 25, y - 40), font_size=70, color=(255, 255, 255, 230)
    )

    return image


def main():
    # Create the background with gradient
    bg = create_gradient_background(WIDTH, HEIGHT, PRIMARY_COLOR, SECONDARY_COLOR)

    # Add decorative elements
    bg = add_circles(bg)

    # Add logo
    bg = add_logo(bg)

    # Add app name
    bg = add_text(bg, "Otto", (250, 220), font_size=48)

    # Add installation instructions
    bg = add_instructions(bg)

    # Apply a slight blur for a modern look
    bg = bg.filter(ImageFilter.GaussianBlur(radius=0.5))

    # Create directory if it doesn't exist
    os.makedirs("dmg_resources", exist_ok=True)

    # Save the image
    bg.save("dmg_resources/background.png")
    print("Background image created at dmg_resources/background.png")


if __name__ == "__main__":
    main()
