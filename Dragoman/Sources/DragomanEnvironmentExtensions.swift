//
//  File.swift
//  
//
//  Created by Tomas Green on 2021-06-23.
//

import SwiftUI
import Combine

/// Automatic Translated Text view, used together with dragoman
public struct ATText: View {
    @EnvironmentObject var dragoman: Dragoman
    var text: LocalizedStringKey
    public init(_ text:LocalizedStringKey) {
        self.text = text
    }
    public var body: some View {
        Text(text, bundle: dragoman.bundle)
    }
}
