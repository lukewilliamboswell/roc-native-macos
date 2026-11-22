// Row templates (`TEMPLATE`), decoded once and cloned per row (`INST`).

import AppKit

extension Host {
    // MARK: Templates

    func decodeTemplate(_ bytes: [UInt8]) -> Template {
        var r = Reader(bytes)
        func node() -> Node {
            switch r.u8() {
            case 1:
                let n = Node(.element(r.expandedName()))
                _ = r.u8()
                for _ in 0..<r.u8() { let name = r.expandedName(); n.attrs[name] = r.str() }
                for _ in 0..<r.u8() { n.append(node()) }
                return n
            case 2:
                let n = Node(.text); n.text = r.str(); return n
            case 3:
                _ = r.str(); return Node(.comment)
            default:
                fatal("unknown template node")
            }
        }
        let root = node()
        var holes: [Template.Hole] = []
        for _ in 0..<r.u8() {
            let kind = r.u8()
            var path: [Int] = []
            for _ in 0..<r.u8() { _ = r.u8(); path.append(Int(r.u8())) }
            var attr: String? = nil
            switch kind {
            case 2: attr = r.expandedName()
            case 3:
                let handler = r.u8(), type = r.str(), payloadKind = r.u8()
                let policies = r.u32()
                var target = root
                for i in path { target = target.children[i] }
                target.listeners[type] = (UInt32(handler), payloadKind, policies)
            case 6: attr = Host.propertyName(r.u8())
            default: break
            }
            holes.append(Template.Hole(kind: kind, path: path, attr: attr))
        }
        return Template(root: root, holes: holes)
    }
}
