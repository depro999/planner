import SwiftUI
import UIKit

extension Color {
    init(hex: String) {
        let cleanHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        
        switch cleanHex.lowercased() {
        case "blue": self = .blue
        case "red": self = .red
        case "green": self = .green
        case "orange": self = .orange
        case "purple": self = .purple
        case "pink": self = .pink
        case "yellow": self = .yellow
        case "gray", "grey": self = .gray
        case "cyan": self = .cyan
        case "indigo": self = .indigo
        case "mint": self = .mint
        case "teal": self = .teal
        case "brown": self = .brown
        case "black": self = .black
        case "white": self = .white
        default:
            var int: UInt64 = 0
            Scanner(string: cleanHex).scanHexInt64(&int)
            let a, r, g, b: UInt64
            switch cleanHex.count {
            case 3:
                (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
            case 6:
                (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
            case 8:
                (a, r, g, b) = (255, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
            default:
                (a, r, g, b) = (255, 0, 122, 255)
            }
            self.init(
                .sRGB,
                red: Double(r) / 255.0,
                green: Double(g) / 255.0,
                blue: Double(b) / 255.0,
                opacity: Double(a) / 255.0
            )
        }
    }

    func toHex() -> String {
        let uiColor = UIColor(self)
        
        guard let srgbSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let cgColor = uiColor.cgColor.converted(to: srgbSpace, intent: .defaultIntent, options: nil),
              let components = cgColor.components else {
            return "#007AFF"
        }
        
        let r: Float
        let g: Float
        let b: Float
        
        if components.count >= 3 {
            r = Float(components[0]) // extrae el Rojo
            g = Float(components[1]) // extrae el Verde
            b = Float(components[2]) // extrae el Azul
        } else if components.count >= 1 {
            // Para tonos monocromáticos (negro, blanco, gris)
            r = Float(components[0])
            g = Float(components[0])
            b = Float(components[0])
        } else {
            return "#007AFF"
        }
        
        let redByte = Int(max(0, min(255, lroundf(r * 255.0))))
        let greenByte = Int(max(0, min(255, lroundf(g * 255.0))))
        let blueByte = Int(max(0, min(255, lroundf(b * 255.0))))
        
        return String(format: "#%02X%02X%02X", redByte, greenByte, blueByte)
    }
}
