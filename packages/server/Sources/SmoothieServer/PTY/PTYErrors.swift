import Foundation

enum PTYError: Error, CustomStringConvertible {
    case openMaster(Int32)
    case grantpt(Int32)
    case unlockpt(Int32)
    case ptsname(Int32)
    case openSlave(Int32)
    case spawn(Int32)
    case write(Int32)
    case alreadyTerminated

    var description: String {
        switch self {
        case .openMaster(let e): return "posix_openpt failed: errno \(e)"
        case .grantpt(let e):    return "grantpt failed: errno \(e)"
        case .unlockpt(let e):   return "unlockpt failed: errno \(e)"
        case .ptsname(let e):    return "ptsname_r failed: errno \(e)"
        case .openSlave(let e):  return "open(slave) failed: errno \(e)"
        case .spawn(let e):      return "posix_spawn failed: errno \(e)"
        case .write(let e):      return "write failed: errno \(e)"
        case .alreadyTerminated: return "PTY process already terminated"
        }
    }
}
