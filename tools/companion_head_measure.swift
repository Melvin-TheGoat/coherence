import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
struct Img {
    var w: Int, h: Int, px: [UInt8]  // premultiplied RGBA
    init(path: String) {
        let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
        let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)!
        w = cg.width; h = cg.height
        px = [UInt8](repeating: 0, count: w*h*4)
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    func a(_ x: Int, _ y: Int) -> Int { Int(px[(y*w+x)*4+3]) }
    func rgb(_ x: Int, _ y: Int) -> (Int,Int,Int) { let i=(y*w+x)*4; let a=max(1,Int(px[i+3])); return (Int(px[i])*255/a, Int(px[i+1])*255/a, Int(px[i+2])*255/a) }
}
func loadCG(_ path: String) -> CGImage { let s = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!; return CGImageSourceCreateImageAtIndex(s, 0, nil)! }
func savePNG(_ cg: CGImage, _ path: String) {
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, cg, nil); CGImageDestinationFinalize(d)
}
import Foundation
struct Head { var name: String; var eyeL: (Double,Double); var eyeR: (Double,Double); var eyeTop: Double; var cx: Double; var browW: Double; var browL: Double; var skull: Double; var top: Double; var topCentral: Double }
// All in canvas units of the given image (caller divides by scale).
func measureHead(_ im: Img, name: String) -> Head {
    let W = im.w, H = im.h
    var lab = [Bool](repeating: false, count: W*H)
    func dark(_ x:Int,_ y:Int)->Bool { guard im.a(x,y) > 220 else {return false}; let (r,g,b)=im.rgb(x,y); return r+g+b < 110 }
    var comps: [(n:Int,sx:Double,sy:Double,y0:Int)] = []
    for y in Int(Double(H)*0.05)..<Int(Double(H)*0.6) { for x in 0..<W where !lab[y*W+x] && dark(x,y) {
        var st=[(x,y)]; lab[y*W+x]=true; var c=(n:0,sx:0.0,sy:0.0,y0:y)
        while let (cx,cy)=st.popLast() { c.n+=1; c.sx+=Double(cx); c.sy+=Double(cy); c.y0=min(c.y0,cy)
            for (dx,dy) in [(1,0),(-1,0),(0,1),(0,-1)] { let nx=cx+dx, ny=cy+dy; if nx>=0&&ny>=0&&nx<W&&ny<H && !lab[ny*W+nx] && dark(nx,ny) { lab[ny*W+nx]=true; st.append((nx,ny)) } } }
        comps.append(c) } }
    // two biggest blobs that are side by side (similar y)
    let big = comps.sorted{$0.n>$1.n}
    var e1 = big[0], e2 = big[1]
    for j in 1..<min(6,big.count) { if abs(big[j].sy/Double(big[j].n) - big[0].sy/Double(big[0].n)) < Double(H)*0.03 && abs(big[j].sx/Double(big[j].n) - big[0].sx/Double(big[0].n)) > Double(W)*0.08 { e2 = big[j]; break } }
    if e1.sx/Double(e1.n) > e2.sx/Double(e2.n) { swap(&e1,&e2) }
    let L=(e1.sx/Double(e1.n), e1.sy/Double(e1.n)), R=(e2.sx/Double(e2.n), e2.sy/Double(e2.n))
    let cx = (L.0+R.0)/2
    let eyeTop = Double(min(e1.y0, e2.y0))
    func seg(_ y: Int) -> (Int,Int)? { let c = Int(cx); guard im.a(c,y) > 200 else { return nil }
        var lo=c, hi=c; while lo>0 && im.a(lo-1,y)>200 { lo-=1 }; while hi<W-1 && im.a(hi+1,y)>200 { hi+=1 }; return (lo,hi) }
    let browY = Int(eyeTop)
    let b = seg(browY) ?? (0,0)
    let browW = Double(b.1-b.0)
    var skull = 0
    for y in 0..<browY { if let s = seg(y), Double(s.1-s.0) > 0.55*browW { skull = y; break } }
    var top = 0; outer: for y in 0..<H { for x in 0..<W where im.a(x,y) > 200 { top = y; break outer } }
    var topC = 0; let band = Int(0.12*browW)
    outer2: for y in 0..<H { for x in max(0,Int(cx)-band)..<min(W,Int(cx)+band) where im.a(x,y) > 200 { topC = y; break outer2 } }
    return Head(name: name, eyeL: L, eyeR: R, eyeTop: eyeTop, cx: cx, browW: browW, browL: Double(b.0), skull: Double(skull), top: Double(top), topCentral: Double(topC))
}
func scaled(_ h: Head, _ s: Double) -> Head { var o=h; o.eyeL=(h.eyeL.0/s,h.eyeL.1/s); o.eyeR=(h.eyeR.0/s,h.eyeR.1/s); o.eyeTop/=s; o.cx/=s; o.browW/=s; o.browL/=s; o.skull/=s; o.top/=s; o.topCentral/=s; return o }
func headWithEyes(_ im: Img, s: Double, L: (Double,Double), R: (Double,Double), eyeTop: Double) -> Head {
    // inputs in canvas units; recompute browW and skull at 2x
    let W = im.w
    let cx = (L.0+R.0)/2*s
    func seg(_ y: Int) -> (Int,Int)? { let c = Int(cx); guard im.a(c,y) > 200 else { return nil }
        var lo=c, hi=c; while lo>0 && im.a(lo-1,y)>200 { lo-=1 }; while hi<W-1 && im.a(hi+1,y)>200 { hi+=1 }; return (lo,hi) }
    let by = Int(eyeTop*s); let b = seg(by)!
    let browW = Double(b.1-b.0)
    var skull = 0; for y in 0..<by { if let q = seg(y), Double(q.1-q.0) > 0.55*browW { skull = y; break } }
    var top = 0; outer: for y in 0..<im.h { for x in 0..<W where im.a(x,y) > 200 { top = y; break outer } }
    var topC = 0; let band = Int(0.12*browW)
    outer2: for y in 0..<im.h { for x in max(0,Int(cx)-band)..<min(W,Int(cx)+band) where im.a(x,y) > 200 { topC = y; break outer2 } }
    return Head(name: "", eyeL: L, eyeR: R, eyeTop: eyeTop, cx: cx/s, browW: browW/s, browL: Double(b.0)/s, skull: Double(skull)/s, top: Double(top)/s, topCentral: Double(topC)/s)
}
let overrides: [String: ((Double,Double),(Double,Double),Double)] = [
    "redpanda-1": ((275,405),(389,400),393),
    "dragon-6": ((287,247),(389,247),238),
    "dragon-7": ((287,243),(389,243),234),
]
func creatureHead(_ c: String, _ n: Int) -> Head {
    let key = "\(c)-\(n)"; let im = Img(path: "\(masterDir)\(key).png")
    if let o = overrides[key] { var h = headWithEyes(im, s: 2, L: o.0, R: o.1, eyeTop: o.2); h.name = key; return h }
    return scaled(measureHead(im, name: key), 2)
}

// Run from the repo root.
let masterDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] + "/" : "mockups/companions/master/"
let otto = measureHead(Img(path: "Shared/Assets.xcassets/OttoAura4.imageset/OttoAura4.png"), name: "otto")
print(String(format: "otto steady: cx %.1f skull %.1f browW %.1f eyeTop %.1f top %.1f topCentral %.1f",
             otto.cx, otto.skull, otto.browW, otto.eyeTop, otto.top, otto.topCentral))
for c in ["redpanda", "tiger", "phoenix", "dragon"] {
    print("\(c):")
    for n in 1...7 {
        var h = creatureHead(c, n)
        // The dragon's horns widen its brow row; its brow width is by hand.
        if c == "dragon" { h.browW = [200, 200, 212, 220, 219, 228, 228][n - 1] }
        print(String(format: "    .init(cx: %.1f, skull: %.1f, browW: %.1f, eyeTop: %.1f, top: %.1f, topCentral: %.1f),",
                     h.cx, h.skull, h.browW, h.eyeTop, h.top, h.topCentral))
    }
}
