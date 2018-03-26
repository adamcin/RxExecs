//
//  RxExecsANSI.swift
//  RxExecs
//

import Foundation
import AppKit

public enum SGRCode: Int {
    case allReset = 0
    
    case intensityBold = 1
    case intensityFaint = 2
    case intensityNormal = 22
    
    case italicOn = 3
    
    case underlineSingle = 4
    case underlineDouble = 21
    case underlineNone = 24
    
    case fgBlack = 30
    case fgRed = 31
    case fgGreen = 32
    case fgYellow = 33
    case fgBlue = 34
    case fgMagenta = 35
    case fgCyan = 36
    case fgWhite = 37
    case fgReset = 39
    
    case bgBlack = 40
    case bgRed = 41
    case bgGreen = 42
    case bgYellow = 43
    case bgBlue = 44
    case bgMagenta = 45
    case bgCyan = 46
    case bgWhite = 47
    case bgReset = 49
    
    case fgBrightBlack = 90
    case fgBrightRed = 91
    case fgBrightGreen = 92
    case fgBrightYellow = 93
    case fgBrightBlue = 94
    case fgBrightMagenta = 95
    case fgBrightCyan = 96
    case fgBrightWhite = 97
    
    case bgBrightBlack = 100
    case bgBrightRed = 101
    case bgBrightGreen = 102
    case bgBrightYellow = 103
    case bgBrightBlue = 104
    case bgBrightMagenta = 105
    case bgBrightCyan = 106
    case bgBrightWhite = 107
    
    public var isIntensity: Bool {
        switch self {
        case .intensityBold, .intensityFaint, .intensityNormal: return true
        default: return false
        }
    }
    
    public var isUnderline: Bool {
        switch self {
        case .underlineDouble, .underlineNone, .underlineSingle: return true
        default: return false
        }
    }
    
    public var isReset: Bool {
        switch self {
        case .allReset, .fgReset, .bgReset, .underlineNone, .intensityNormal: return true
        default: return false
        }
    }
    
    public var isColor: Bool {
        return self.rawValue >= 30 && !self.isReset
    }
    
    public var isFgColor: Bool {
        return isColor && self.rawValue % 30 < 10
    }
    
    public var isBgColor: Bool {
        return isColor && !isFgColor
    }
    
    public var isBrightColor: Bool {
        return isColor && self.rawValue >= 90
    }
    
    public var hue: CGFloat? {
        switch self {
        case .fgYellow, .bgYellow: return 1.0 / 6.0
        case .fgGreen, .bgGreen: return 2.0 / 6.0
        case .fgCyan, .bgCyan: return 3.0 / 6.0
        case .fgBlue, .bgBlue: return 4.0 / 6.0
        case .fgMagenta, .bgMagenta: return 5.0 / 6.0
        case .fgRed, .bgRed: return 6.0 / 6.0
        default: return nil
        }
    }
    
    public func nsColor() -> NSColor? {
        guard isColor else { return nil }
        
        switch self {
        case .fgBlack, .bgBlack: return NSColor.black
        case .fgBrightBlack, .bgBrightBlack: return NSColor(calibratedWhite: 0.337, alpha: 1.0)
        case .fgWhite, .bgWhite: return NSColor.white
        default: return self.hue.map { hue in return NSColor(calibratedHue: hue, saturation: isBrightColor ? 0.4 : 1.0, brightness: 1.0, alpha: 1.0) }
        }
    }
    
    public func endsRangeForCode(_ startCode: SGRCode) -> Bool {
        guard !startCode.isReset else { return false }
        guard self != .allReset else { return true }

        if self == .fgReset || self.isFgColor {
            return startCode.isFgColor
        } else if self == .bgReset || self.isBgColor {
            return startCode.isBgColor
        } else if self.isUnderline {
            return startCode.isUnderline
        } else if self.isIntensity {
            return startCode.isIntensity
        }
        
        return false
    }
}

public enum SGRCodeDictKey: String, CustomStringConvertible {
    case Code
    case Location
    
    public var description: String {
        return self.rawValue
    }
}

public enum SGRAttrDictKey: String, CustomStringConvertible {
    case Range
    case AttributeName
    case AttributeValue
    
    public var description: String {
        return self.rawValue
    }
}

let escapeCSI = "\u{1B}["
let escapeSGREnd = "m"

enum ANSIError: Error {
    case parseError
}

let defaultFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
let defaultColor = NSColor.black
let defaultMapping: (SGRCode) -> SGRCode = { $0 }

public struct ANSI {
    public let fgColor: NSColor
    public let font: NSFont
    public let decodeMapping: (SGRCode) -> SGRCode
    public let encodeMapping: (SGRCode) -> SGRCode
    
    public init() {
        self.font = defaultFont
        self.fgColor = defaultColor
        self.decodeMapping = defaultMapping
        self.encodeMapping = defaultMapping
    }
    
    public init(font: NSFont, fgColor: NSColor) {
        self.font = font
        self.fgColor = fgColor
        self.decodeMapping = defaultMapping
        self.encodeMapping = defaultMapping
    }
    
    public init(font: NSFont, fgColor: NSColor, decodeMapping: @escaping (SGRCode) -> SGRCode, encodeMapping: @escaping (SGRCode) -> SGRCode) {
        self.font = font
        self.fgColor = fgColor
        self.decodeMapping = decodeMapping
        self.encodeMapping = encodeMapping
    }
    
    public func stripANSI(encodedString val: String, otherColor: NSColor? = nil, otherFont: NSFont? = nil) -> NSAttributedString {
        let (clean, _) = self.parseANSICodes(encodedString: val)
        let firstAttrs: [NSAttributedStringKey: Any] = [
            NSAttributedStringKey.font: otherFont ?? self.font,
            NSAttributedStringKey.foregroundColor: otherColor ?? self.fgColor
        ]
        
        let nsa = NSMutableAttributedString(string: clean, attributes: firstAttrs)
        return nsa
    }
    
    public func decodeANSI(encodedString val: String) -> NSAttributedString {
        return self.decodeANSI(encodedString: val, openCodes: []).0
    }
    
    public func decodeANSI(encodedString val: String, openCodes: [SGRCode]) -> (NSAttributedString, [SGRCode]) {
        let (clean, codes) = self.parseANSICodes(encodedString: val)
        let firstAttrs: [NSAttributedStringKey: Any] = [
            NSAttributedStringKey.font: self.font,
            NSAttributedStringKey.foregroundColor: self.fgColor
        ]
        
        let nsa = NSMutableAttributedString(string: clean, attributes: firstAttrs)
        
        var resets = Dictionary<SGRCode, Int>()
        var notReset = Set<SGRCode>()
        
        let allCodes = [(0, openCodes)] + codes
        for pair in allCodes.reversed() {
            let (startIndex, codesAt) = pair
            for codeAt in codesAt {
                var minEndIndex = clean.count
                var wasReset = false
                for mayReset in resets {
                    let (resetCode, index) = mayReset
                    if resetCode.endsRangeForCode(codeAt) {
                        wasReset = true
                        if index < minEndIndex {
                            minEndIndex = index
                        }
                    }
                }
                
                resets[codeAt] = startIndex
                let realRange = NSMakeRange(startIndex, minEndIndex - startIndex)
                if !codeAt.isReset {
                    if !wasReset {
                        notReset.insert(codeAt)
                    }
                    
                    let preferredCode = self.decodeMapping(codeAt)
                    if preferredCode.isFgColor {
                        nsa.addAttribute(NSAttributedStringKey.foregroundColor, value: preferredCode.nsColor()!, range: realRange)
                    } else if preferredCode.isBgColor {
                        nsa.addAttribute(NSAttributedStringKey.backgroundColor, value: preferredCode.nsColor()!, range: realRange)
                    } else if preferredCode.isIntensity {
                        switch preferredCode {
                        case .intensityBold:
                            let newFont = NSFontManager.shared.convert(self.font, toHaveTrait: NSFontTraitMask.boldFontMask)
                            nsa.addAttribute(NSAttributedStringKey.font, value: newFont, range: realRange)
                        case .intensityFaint:
                            let newFont = NSFontManager.shared.convert(self.font, toHaveTrait: NSFontTraitMask.unboldFontMask)
                            nsa.addAttribute(NSAttributedStringKey.font, value: newFont, range: realRange)
                        default: break
                        }
                    } else if preferredCode.isUnderline {
                        var underlineStyle = NSUnderlineStyle.styleNone
                        switch preferredCode {
                        case .underlineDouble: underlineStyle = .styleDouble
                        case .underlineSingle: underlineStyle = .styleSingle
                        default: break
                        }
                        nsa.addAttribute(NSAttributedStringKey.underlineStyle, value: underlineStyle.rawValue, range: realRange)
                    }
                }
            }
        }
        
        return (nsa, Array(notReset))
    }
    
    func parseANSICodes(encodedString val: String) -> (String, [(Int, [SGRCode])]) {
        var clean = ""
        var codes = Array<(Int, [SGRCode])>()
        
        guard val.count > escapeCSI.count else { return (val, codes) }
        
        var searchRange: Range<String.Index>? = Range(uncheckedBounds: (lower: val.indices.startIndex, upper: val.indices.endIndex))
        
        while searchRange != nil {
            if let csi = val.range(of: escapeCSI, options: NSString.CompareOptions.literal, range: searchRange, locale: nil), let sgrEnd = val.range(of: "m", options: NSString.CompareOptions.literal, range: (csi.upperBound ..< searchRange!.upperBound), locale: nil) {
                
                // append to clean and reset search range for next iter
                clean = clean.appending(val[searchRange!.lowerBound ..< csi.lowerBound])
                searchRange = (sgrEnd.upperBound ..< searchRange!.upperBound)
                
                let codeString = val[csi.upperBound ..< sgrEnd.lowerBound]
                
                guard codeString.count > 0 else {
                    codes.append((clean.count, [SGRCode.allReset]))
                    continue
                }
                
                if let csiCodes = try? codeString.split(separator: ";").map({ (code) -> SGRCode in
                    if let sgrCode = Int(String.init(code)).flatMap(SGRCode.init) {
                        return sgrCode
                    } else {
                        throw ANSIError.parseError
                    }
                }) {
                    codes.append((clean.count, csiCodes))
                }
                
                
            } else {
                clean = clean.appending(val[searchRange!])
                searchRange = nil
            }
        }
        
        return (clean, codes)
    }
}
