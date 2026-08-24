from PIL import Image, ImageDraw

SIZE = 1024
img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# Scooter/moto icon - white on transparent (foreground layer)
# Drawn as simple geometric shapes representing a scooter
cx, cy = SIZE // 2, SIZE // 2

def s(v):  # scale value from 0-100 to pixel
    return int(v / 100 * SIZE)

# Body of scooter (main horizontal ellipse)
draw.ellipse([s(18), s(38), s(82), s(62)], fill="white")

# Windshield / front fairing
draw.polygon([
    (s(65), s(30)), (s(80), s(30)), (s(82), s(50)), (s(65), s(50))
], fill="white")

# Rider seat area
draw.ellipse([s(35), s(28), s(65), s(46)], fill="white")

# Handlebar
draw.rectangle([s(72), s(26), s(84), s(34)], fill="white")

# Front wheel
draw.ellipse([s(68), s(55), s(92), s(80)], fill="white")
draw.ellipse([s(74), s(61), s(86), s(74)], fill=(255, 109, 0, 255))  # hole

# Rear wheel
draw.ellipse([s(8), s(55), s(32), s(80)], fill="white")
draw.ellipse([s(14), s(61), s(26), s(74)], fill=(255, 109, 0, 255))  # hole

# Exhaust pipe
draw.rectangle([s(10), s(58), s(28), s(62)], fill="white")

# Front fork
draw.line([(s(78), s(50)), (s(80), s(62))], fill="white", width=s(4))

img.save("assets/images/moto_icon.png")
print("OK: assets/images/moto_icon.png generado")
