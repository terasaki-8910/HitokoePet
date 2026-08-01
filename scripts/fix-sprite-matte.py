#!/usr/bin/env python3
"""
ペットのスプライトシート（spritesheet.png / .webp）に焼き込まれた「白マット汚染」と
アルファチャンネルの縁ノイズを除去する。

背景1（白マット汚染）: petdex.dev 等からダウンロードされる一部のスプライトは、半透明な縁の
ピクセル（アンチエイリアス部分）が白背景に対して合成された状態でエクスポート
されている（straight alpha だが RGB が白側にブレンド済み）。これを透過窓の上で
そのまま premultiplied alpha 合成すると、白以外の背景（特に濃い色・カラフルな
壁紙）に対してキャラクターの縁がうっすら白く霞んだように見える
（HitokoePet の実機フィードバック「白飛び」「縁のノイズ」の根本原因の1つ、
2026-08-01 に特定）。

このスクリプトは各半透明ピクセル（alpha_floor <= alpha < 255）について、白マットで
ブレンドされたと仮定して逆算し、素のキャラクター色を復元する:
    true_color = (observed - 255*(1-alpha)) / alpha
alpha が極端に小さい（ほぼ透明な）ピクセルは逆算の分母が0に近づき、量子化誤差が
大きく増幅されて逆にノイズを生む（後述の背景2の一因にもなる）ため、alpha_floor
未満のピクセルは意図的に触らない。不透明(alpha=255)・完全透明(alpha=0)も変更しない。

背景2（アルファ縁ノイズ、2026-08-01 白マット修正後も残存と実機フィードバックで判明）:
上記の白マット汚染とは別に、素材そのもの（AI生成+背景除去+WebP圧縮を経由したと
見られる）のアルファチャンネルに、シルエット境界沿いの単発ノイズ（塩コショウ状の
alpha値の飛び）が焼き込まれている。ダウンロード直後の未加工画像で検証済みで、
白マット除去の有無に関わらず同一パターンで存在する（= unmatte_white が原因ではない）。
最近傍拡大（このアプリの描画方式）ではこれが縁のジャギー・粒状ノイズとして見え、
特に白背景でどんな背景色より目立つ（ズレた色をマスクする周辺コンテキストが無いため）。
これはアルファチャンネルにのみ 3x3 メディアンフィルタをかけて除去する（RGBは触らない
ので色のにじみ・ぼやけは発生しない）。

使い方:
    python scripts/fix-sprite-matte.py <入力画像> <出力画像>
    python scripts/fix-sprite-matte.py --inplace <画像パス>...

新しいペットをインストールした際、縁に白っぽい滲み・ジャギーが見えたら
このスクリプトを spritesheet.png / spritesheet.webp の両方に対して実行する
（`~/.petdex/pets/<pet>/` 以下）。
"""
import sys
from pathlib import Path

from PIL import Image, ImageFilter

ALPHA_FLOOR = 32
DESPECKLE_SIZE = 3


def unmatte_white(img: Image.Image, alpha_floor: int = ALPHA_FLOOR) -> Image.Image:
    img = img.convert("RGBA")
    w, h = img.size
    px = img.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0 or a == 255 or a < alpha_floor:
                continue
            an = a / 255.0
            nr = (r - 255 * (1 - an)) / an
            ng = (g - 255 * (1 - an)) / an
            nb = (b - 255 * (1 - an)) / an
            px[x, y] = (
                max(0, min(255, round(nr))),
                max(0, min(255, round(ng))),
                max(0, min(255, round(nb))),
                a,
            )
    r, g, b, a = img.split()
    a = a.filter(ImageFilter.MedianFilter(size=DESPECKLE_SIZE))
    return Image.merge("RGBA", (r, g, b, a))


def main(argv: list[str]) -> int:
    if len(argv) >= 1 and argv[0] == "--inplace":
        if len(argv) < 2:
            print(__doc__)
            return 1
        for path_str in argv[1:]:
            path = Path(path_str)
            img = Image.open(path)
            fixed = unmatte_white(img)
            save_kwargs = {"lossless": True} if path.suffix.lower() == ".webp" else {}
            fixed.save(path, **save_kwargs)
            print(f"fixed in place: {path}")
        return 0

    if len(argv) != 2:
        print(__doc__)
        return 1

    src, dst = Path(argv[0]), Path(argv[1])
    img = Image.open(src)
    fixed = unmatte_white(img)
    save_kwargs = {"lossless": True} if dst.suffix.lower() == ".webp" else {}
    fixed.save(dst, **save_kwargs)
    print(f"wrote {dst}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
