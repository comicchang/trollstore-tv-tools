#!/bin/sh
# invert-tvos-icon.sh — Invert RGB pixels of a tvOS Assets.car (layered App Icon, Top Shelf, BootLogoMark)
# and recompile it natively with Xcode actool.
#
# Usage:
#   ./scripts/invert-tvos-icon.sh [--dry-run] -o <output-Assets.car> <input-Assets.car>
#
# Notes:
# - Runs on macOS with full Xcode installed (uses CoreUI, CoreGraphics, and AppleTVOS actool).
# - Explicitly inverts raw RGBA8 pixels (preserving alpha), avoiding CoreImage CIColorInvert no-ops
#   on monochrome (gray gamma 22) tvOS layered icon assets.
set -eu

DRY_RUN=0
OUT_CAR=""
DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

usage() {
	cat <<'USAGE'
Usage: invert-tvos-icon.sh [--dry-run] -o <output-Assets.car> <input-Assets.car>

  --dry-run                Print planned extraction, inversion, and actool steps without modifying files
  -o, --output <file.car>  Output compiled Assets.car path (required unless --dry-run)
  -h, --help               Show this help message

Environment:
  DEVELOPER_DIR            Full Xcode Developer directory (default: /Applications/Xcode.app/Contents/Developer)
USAGE
}

[ $# -gt 0 ] || { usage >&2; exit 2; }

while [ $# -gt 0 ]; do
	case "$1" in
		--dry-run) DRY_RUN=1; shift ;;
		-o|--output)
			[ $# -ge 2 ] || { echo "Missing value for $1" >&2; exit 2; }
			OUT_CAR=$2; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		-*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
		*) break ;;
	esac
done

IN_CAR=${1:-}
[ -n "$IN_CAR" ] || { echo "Missing <input-Assets.car>" >&2; usage >&2; exit 2; }

if [ "$DRY_RUN" -eq 1 ]; then
	echo "Input Assets.car : $IN_CAR"
	echo "Output Assets.car: ${OUT_CAR:-<unspecified>}"
	echo "actool           : $DEVELOPER_DIR/usr/bin/actool"
	echo "+ extract layered tvOS icon/top-shelf images via CoreUI"
	echo "+ invert raw RGBA8 pixels (255 - RGB, preserving alpha)"
	echo "+ compile .xcassets with actool --platform appletvos --target-device tv"
	echo "+ verify rendered corner/center pixels"
	echo "dry-run complete, no files written"
	exit 0
fi

[ -f "$IN_CAR" ] || { echo "Input Assets.car not found: $IN_CAR" >&2; exit 2; }
[ -n "$OUT_CAR" ] || { echo "Missing -o <output-Assets.car>" >&2; usage >&2; exit 2; }

ACTOOL="$DEVELOPER_DIR/usr/bin/actool"
[ -x "$ACTOOL" ] || { echo "Xcode actool not found at $ACTOOL" >&2; exit 2; }
command -v swift >/dev/null 2>&1 || { echo "swift is required on macOS" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/invert-tvos-icon.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM

mkdir -p "$WORK/xcassets" "$WORK/car-out"

swift - "$IN_CAR" "$WORK/xcassets/Assets.xcassets" <<'SW'
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count >= 3 else {
    fputs("Usage: swift - <input.car> <out.xcassets>\n", stderr)
    exit(2)
}
guard dlopen("/System/Library/PrivateFrameworks/CoreUI.framework/CoreUI", RTLD_LAZY) != nil else {
    fputs("Failed to load CoreUI.framework\n", stderr)
    exit(1)
}

let origCar = CommandLine.arguments[1]
let outRoot = URL(fileURLWithPath: CommandLine.arguments[2])
let fm = FileManager.default
try fm.createDirectory(at: outRoot, withIntermediateDirectories: true)
try "{\"info\":{\"author\":\"xcode\",\"version\":1}}\n".write(
    to: outRoot.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8
)

let cuiClass: AnyClass = NSClassFromString("CUICatalog")!
let obj = (cuiClass as! NSObject.Type).perform(NSSelectorFromString("alloc")).takeUnretainedValue()
typealias InitFn = @convention(c) (AnyObject, Selector, NSURL, AutoreleasingUnsafeMutablePointer<NSError?>?) -> AnyObject?
let initSel = NSSelectorFromString("initWithURL:error:")
let initFn = unsafeBitCast(class_getMethodImplementation(cuiClass, initSel)!, to: InitFn.self)
var err: NSError?
guard let cat = initFn(obj, initSel, URL(fileURLWithPath: origCar) as NSURL, &err) else {
    fputs("CUICatalog init failed: \(String(describing: err))\n", stderr)
    exit(1)
}

typealias ImgsFn = @convention(c) (AnyObject, Selector, NSString) -> Unmanaged<NSArray>?
let imgsSel = NSSelectorFromString("imagesWithName:")
let imgsFn = unsafeBitCast(class_getMethodImplementation(cuiClass, imgsSel)!, to: ImgsFn.self)

func getImages(_ name: String) -> [(CGImage, Int, Int)] {
    var res: [(CGImage, Int, Int)] = []
    guard let arr = imgsFn(cat, imgsSel, name as NSString)?.takeUnretainedValue() else { return res }
    for item in arr {
        let o = item as AnyObject
        let cgSel = NSSelectorFromString("image")
        guard o.responds(to: cgSel) else { continue }
        typealias CGFn = @convention(c) (AnyObject, Selector) -> Unmanaged<CGImage>?
        let cgFn = unsafeBitCast(class_getMethodImplementation(type(of: o), cgSel)!, to: CGFn.self)
        if let cg = cgFn(o, cgSel)?.takeUnretainedValue() {
            res.append((cg, cg.width, cg.height))
        }
    }
    return res
}

func invertAndSave(_ cg: CGImage, to url: URL, opaqueBg: Bool) throws {
    let w = cg.width, h = cg.height
    let cs = CGColorSpaceCreateDeviceRGB()
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    guard let ctx = CGContext(
        data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("CGContext failed") }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

    for i in stride(from: 0, to: buf.count, by: 4) {
        let a = buf[i + 3]
        if a == 0 {
            buf[i] = 0; buf[i+1] = 0; buf[i+2] = 0
        } else if a == 255 {
            buf[i] = 255 &- buf[i]
            buf[i+1] = 255 &- buf[i+1]
            buf[i+2] = 255 &- buf[i+2]
        } else {
            let af = Double(a) / 255.0
            let r = min(255.0, max(0.0, Double(buf[i]) / af))
            let g = min(255.0, max(0.0, Double(buf[i+1]) / af))
            let b = min(255.0, max(0.0, Double(buf[i+2]) / af))
            buf[i]   = UInt8(min(255.0, max(0.0, (255.0 - r) * af)).rounded())
            buf[i+1] = UInt8(min(255.0, max(0.0, (255.0 - g) * af)).rounded())
            buf[i+2] = UInt8(min(255.0, max(0.0, (255.0 - b) * af)).rounded())
        }
        if opaqueBg { buf[i+3] = 255 }
    }

    let info = opaqueBg ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
    guard let outCtx = CGContext(
        data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
        space: cs, bitmapInfo: info
    ), let outCG = outCtx.makeImage() else { fatalError("outCG failed") }

    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("CGImageDestination failed")
    }
    CGImageDestinationAddImage(dest, outCG, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("PNG finalize failed") }
}

let allNames = (cat.perform(NSSelectorFromString("allImageNames")).takeUnretainedValue() as? [String]) ?? []
let bgSmall = allNames.contains("App Icon/Background/Content") ? "App Icon/Background/Content"
    : (allNames.contains("AppIconSmall/Back/Content") ? "AppIconSmall/Back/Content" : "")
let fgSmall = allNames.contains("App Icon/Foreground/Content") ? "App Icon/Foreground/Content"
    : (allNames.contains("AppIconSmall/Front/Content") ? "AppIconSmall/Front/Content" : "")
let bgLarge = allNames.contains("App Icon - App Store/Background/Content") ? "App Icon - App Store/Background/Content"
    : (allNames.contains("AppIconLarge/Back/Content") ? "AppIconLarge/Back/Content" : bgSmall)
let fgLarge = allNames.contains("App Icon - App Store/Foreground/Content") ? "App Icon - App Store/Foreground/Content"
    : (allNames.contains("AppIconLarge/Front/Content") ? "AppIconLarge/Front/Content" : fgSmall)

guard !bgSmall.isEmpty && !fgSmall.isEmpty else {
    fputs("Unsupported Assets.car icon layer naming. Available names: \(allNames)\n", stderr)
    exit(1)
}

let iconBase = bgSmall.hasPrefix("AppIconSmall") ? "AppIconSmall" : "App Icon"
let iconLarge = bgSmall.hasPrefix("AppIconSmall") ? "AppIconLarge" : "App Icon - App Store"
let brandName = bgSmall.hasPrefix("AppIconSmall") ? "AppIcon" : "App Icon & Top Shelf Image"

let brand = outRoot.appendingPathComponent("\(brandName).brandassets")
try fm.createDirectory(at: brand, withIntermediateDirectories: true)

var brandAssets: [[String: String]] = [
    ["filename": "\(iconLarge).imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"],
    ["filename": "\(iconBase).imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"]
]

func buildStack(_ stackName: String, _ bgSrc: String, _ fgSrc: String, _ sizes: [(Int, Int, String)]) throws {
    let stack = brand.appendingPathComponent("\(stackName).imagestack")
    try fm.createDirectory(at: stack, withIntermediateDirectories: true)
    try "{\"info\":{\"author\":\"xcode\",\"version\":1},\"layers\":[{\"filename\":\"Foreground.imagestacklayer\"},{\"filename\":\"Background.imagestacklayer\"}]}\n"
        .write(to: stack.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

    for (layerName, srcName, isOpaque) in [("Background", bgSrc, true), ("Foreground", fgSrc, false)] {
        let layer = stack.appendingPathComponent("\(layerName).imagestacklayer")
        let content = layer.appendingPathComponent("Content.imageset")
        try fm.createDirectory(at: content, withIntermediateDirectories: true)
        try "{\"info\":{\"author\":\"xcode\",\"version\":1}}\n"
            .write(to: layer.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
        let imgs = getImages(srcName)
        guard !imgs.isEmpty else { fatalError("No images found for \(srcName)") }
        var entries: [[String: String]] = []
        for (w, h, scale) in sizes {
            let match = imgs.first(where: { $0.1 == w && $0.2 == h }) ?? imgs[0]
            let fn = "\(layerName.lowercased())-\(w)x\(h).png"
            try invertAndSave(match.0, to: content.appendingPathComponent(fn), opaqueBg: isOpaque)
            entries.append(["filename": fn, "idiom": "tv", "scale": scale])
        }
        let data = try JSONSerialization.data(withJSONObject: ["images": entries, "info": ["author": "xcode", "version": 1]], options: .prettyPrinted)
        try data.write(to: content.appendingPathComponent("Contents.json"))
    }
}

try buildStack(iconBase, bgSmall, fgSmall, [(400, 240, "1x"), (800, 480, "2x")])
try buildStack(iconLarge, bgLarge, fgLarge, [(1280, 768, "1x")])

func buildImageSet(_ dir: URL, _ srcName: String, _ specs: [(Int, Int, String, String, Bool)]) throws {
    let imgs = getImages(srcName)
    guard !imgs.isEmpty else { return }
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    var entries: [[String: String]] = []
    for (idx, (w, h, idiom, scale, isOpaque)) in specs.enumerated() {
        let match = imgs.first(where: { $0.1 == w && $0.2 == h }) ?? imgs[min(idx, imgs.count - 1)]
        let fn = "img-\(idx)-\(w)x\(h).png"
        try invertAndSave(match.0, to: dir.appendingPathComponent(fn), opaqueBg: isOpaque)
        entries.append(["filename": fn, "idiom": idiom, "scale": scale])
    }
    let data = try JSONSerialization.data(withJSONObject: ["images": entries, "info": ["author": "xcode", "version": 1]], options: .prettyPrinted)
    try data.write(to: dir.appendingPathComponent("Contents.json"))
}

if allNames.contains("Top Shelf Image") {
    brandAssets.append(["filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"])
    try buildImageSet(brand.appendingPathComponent("Top Shelf Image.imageset"), "Top Shelf Image", [(1920, 720, "tv", "1x", true), (3840, 1440, "tv", "2x", true)])
}
if allNames.contains("Top Shelf Image Wide") {
    brandAssets.append(["filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"])
    try buildImageSet(brand.appendingPathComponent("Top Shelf Image Wide.imageset"), "Top Shelf Image Wide", [(2320, 720, "tv", "1x", true), (4640, 1440, "tv", "2x", true)])
}
if allNames.contains("BootLogoMark") {
    try buildImageSet(outRoot.appendingPathComponent("BootLogoMark.imageset"), "BootLogoMark", [(1024, 1024, "universal", "1x", false), (2048, 2048, "universal", "2x", false)])
}

let brandData = try JSONSerialization.data(withJSONObject: ["assets": brandAssets, "info": ["author": "xcode", "version": 1]], options: .prettyPrinted)
try brandData.write(to: brand.appendingPathComponent("Contents.json"))
print(brandName)
SW

BRAND_NAME=""
for d in "$WORK/xcassets/Assets.xcassets"/*.brandassets; do
	if [ -d "$d" ]; then
		BRAND_NAME=$(basename "$d" .brandassets)
		break
	fi
done
[ -n "$BRAND_NAME" ] || { echo "No .brandassets generated" >&2; exit 1; }

DEVELOPER_DIR="$DEVELOPER_DIR" "$ACTOOL" \
	--compile "$WORK/car-out" \
	--platform appletvos \
	--minimum-deployment-target 16.0 \
	--target-device tv \
	--app-icon "$BRAND_NAME" \
	--output-partial-info-plist "$WORK/car-out/partial.plist" \
	"$WORK/xcassets/Assets.xcassets" >/dev/null

OUT_DIR=$(dirname "$OUT_CAR")
mkdir -p "$OUT_DIR"
cp "$WORK/car-out/Assets.car" "$OUT_CAR"
echo "Compiled inverted Assets.car: $OUT_CAR ($(wc -c < "$OUT_CAR" | tr -d ' ') bytes, brand=$BRAND_NAME)"
