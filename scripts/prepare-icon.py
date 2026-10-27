"""Draw the app's own A mark as a PNG; no third-party imaging dependency."""
from pathlib import Path
import json
import struct
import zlib

root = Path(__file__).resolve().parents[1] / 'Sources/Assets.xcassets'
icons = root / 'AppIcon.appiconset'
icons.mkdir(parents=True, exist_ok=True)
size = 1024
pixels = bytearray()
def distance(x, y, ax, ay, bx, by):
    t = max(0, min(1, ((x-ax)*(bx-ax)+(y-ay)*(by-ay))/((bx-ax)**2+(by-ay)**2)))
    return ((x-ax-t*(bx-ax))**2 + (y-ay-t*(by-ay))**2)**.5
for y in range(size):
    pixels.append(0)
    for x in range(size):
        d = min(distance(x,y,284,744,512,260), distance(x,y,512,260,740,744), distance(x,y,398,552,626,552))
        a = max(0, min(1, 40.5-d))
        shade = y/size
        bg = (17+int(7*shade), 24+int(10*shade), 44+int(20*shade))
        fg = (114-int(40*shade), 214-int(60*shade), 255)
        pixels.extend(int(b*(1-a)+f*a) for b,f in zip(bg,fg))
def chunk(name, data):
    return struct.pack('>I',len(data))+name+data+struct.pack('>I',zlib.crc32(name+data))
png = b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',size,size,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(pixels,9))+chunk(b'IEND',b'')
(icons/'AppIcon.png').write_bytes(png)
(root/'Contents.json').write_text(json.dumps({'info':{'author':'xcode','version':1}}))
(icons/'Contents.json').write_text(json.dumps({'images':[{'filename':'AppIcon.png','idiom':'universal','platform':'ios','size':'1024x1024'}],'info':{'author':'xcode','version':1}}))
