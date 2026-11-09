import CoreGraphics
import Foundation
// mouse click X Y [count] | mouse rclick X Y | mouse drag X1 Y1 X2 Y2   (global screen points)
let a = CommandLine.arguments
func post(_ type: CGEventType, _ p: CGPoint, clicks: Int64 = 1) {
    let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)!
    e.setIntegerValueField(.mouseEventClickState, value: clicks)
    e.post(tap: .cghidEventTap)
    usleep(30_000)
}
let n = a.dropFirst(2).compactMap { Double($0) }
if a[1] == "click" {
    let p = CGPoint(x: n[0], y: n[1])
    post(.mouseMoved, p)
    for c in 1...(n.count > 2 ? Int64(n[2]) : 1) { post(.leftMouseDown, p, clicks: c); post(.leftMouseUp, p, clicks: c) }
} else if a[1] == "drag" {
    let p1 = CGPoint(x: n[0], y: n[1]), p2 = CGPoint(x: n[2], y: n[3])
    post(.mouseMoved, p1); post(.leftMouseDown, p1)
    for i in 1...10 { let t = Double(i) / 10; post(.leftMouseDragged, CGPoint(x: p1.x + (p2.x - p1.x) * t, y: p1.y + (p2.y - p1.y) * t)) }
    post(.leftMouseUp, p2)
}
// mouse scroll X Y DY   (lines; negative scrolls content up, i.e. shows what is below)
if a[1] == "scroll" {
    let p = CGPoint(x: n[0], y: n[1])
    post(.mouseMoved, p)
    let e = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: Int32(n[2]), wheel2: 0, wheel3: 0)!
    e.location = p
    e.post(tap: .cghidEventTap)
    usleep(30_000)
}

if a[1] == "rclick" {
    let p = CGPoint(x: n[0], y: n[1])
    post(.mouseMoved, p)
    for t in [CGEventType.rightMouseDown, .rightMouseUp] {
        let e = CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .right)!
        e.setIntegerValueField(.mouseEventClickState, value: 1)
        e.post(tap: .cghidEventTap)
        usleep(30_000)
    }
}
