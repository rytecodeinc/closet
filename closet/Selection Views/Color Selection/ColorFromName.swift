//
//  ColorFromName.swift
//  closet
//
//  Created by Dan Warner on 7/19/25.
//

import Foundation
import SwiftUI

func colorFromName(_ colorName: String) -> Color {
    switch colorName.lowercased() {
    case "beige": return Color("beige")  // Custom color in your Assets
    case "red": return .red
    case "orange": return .orange
    case "yellow": return .yellow
    case "green": return .green
    case "blue": return .blue
    case "purple": return .purple
    case "pink": return .pink
    case "brown": return .brown
    case "black": return .black
    case "gray": return .gray
    case "silver": return Color("silver")  // Custom color in your Assets
    case "gold": return Color("gold")      // Custom color in your Assets
    case "white": return .white
    default: return .clear
    }
}
