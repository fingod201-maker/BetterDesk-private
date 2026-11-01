from PIL import Image
import os

src = r'C:\Users\milaz\BetterDesk\zoom-app-logo.ico'
out = r'C:\Users\milaz\BetterDesk\tools\betterdesk-client-logo.png'

# Open the ICO and select the largest embedded frame (256x256)
im = Image.open(src)
try:
    # ICO plugin supports seeking to a specific size
    im.seek(im.ico.getsize((256, 256)))
except Exception:
    pass
im = im.convert('RGBA')
print('Selected frame size:', im.size, 'mode:', im.mode)

# Downscale to 256x256 (already) and save as optimized PNG
im.save(out, format='PNG', optimize=True)
size = os.path.getsize(out)
print('Wrote', out, 'bytes=', size, 'under_512KiB=', size <= 512 * 1024)
