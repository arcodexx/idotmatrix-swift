import sys
import os
import argparse
import warnings

# Suppress urllib3 SSL warnings
warnings.filterwarnings("ignore", category=UserWarning, module='urllib3')

from apixoo import PixelBeanDecoder
from PIL import Image, ImageSequence

def convert_to_gif(input_path, output_path):
    temp_gif = output_path + ".temp.gif"

    # helper to resize and save
    def save_resized(img_obj, out_path, duration=100):
        frames = []
        try:
            for frame in ImageSequence.Iterator(img_obj):
                resized = frame.copy().resize((32, 32), Image.NEAREST)
                frames.append(resized)
        except Exception:
            pass # End of frames

        if frames:
            frames[0].save(
                out_path,
                save_all=True,
                append_images=frames[1:],
                duration=duration,
                loop=0,
                optimize=False,
                disposal=2
            )
            return True
        return False

    try:
        # STRATEGY 1: Try Opening directly with PIL (Standard GIF/Image)
        # Some Divoom files are just renamed GIFs.
        try:
            with Image.open(input_path) as img:
                duration = img.info.get('duration', 100)
                if save_resized(img, output_path, duration):
                     # print(f"Successfully converted {input_path} (PIL)")
                     return True
        except Exception:
            # Not a standard image, proceed to apixoo
            pass

        # STRATEGY 2: Use Apixoo Decoder
        with open(input_path, 'rb') as f:
            pixel_bean = PixelBeanDecoder.decode_stream(f)

        if pixel_bean:
             # Workaround: apixoo PixelBean might not expose get_frames directly.
             # We save to a temp GIF first using the library's method, then resize.
             pixel_bean.save_to_gif(temp_gif, scale=1)

             try:
                 with Image.open(temp_gif) as img:
                     duration = img.info.get('duration', 100)
                     if save_resized(img, output_path, duration):
                         # print(f"Successfully converted {input_path} (Apixoo)")
                         return True
                     else:
                         print("Failed to extract frames from temp gif")
                         return False
             except Exception as e:
                 print(f"Error resizing temp GIF: {e}")
                 return False
        else:
            print(f"Failed to decode {input_path}")
            return False

    except Exception as e:
        print(f"Error converting file: {e}")
        # import traceback
        # traceback.print_exc()
        return False
    finally:
        if os.path.exists(temp_gif):
            os.remove(temp_gif)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Convert Divoom pixel art files to GIF.')
    parser.add_argument('input', help='Input file path')
    parser.add_argument('output', help='Output GIF path')
    # scale argument removed/ignored as we force 32x32
    parser.add_argument('--scale', type=int, default=1, help='Ignored (forced to 32x32)')

    args = parser.parse_args()

    if not os.path.exists(args.input):
        print(f"Input file not found: {args.input}")
        sys.exit(1)

    success = convert_to_gif(args.input, args.output)

    if success:
        sys.exit(0)
    else:
        sys.exit(1)
