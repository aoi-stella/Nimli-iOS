//
//  PenculaPlainTextField.swift
//  Pencula
//
//  Created by Haruto K. on 2025/02/25.
//

import SwiftUI

/*
 This was created for commonalizing plain text input.
 This wasn't created for secure information(e.g. password, credit card and more!).
 */
struct PenculaPlainTextField: View {
    let title: String
    let placeHolder: String
    @Binding var text: String
    @FocusState var isTyping: Bool
    init(text: Binding<String>, title: String, placeHolder: String) {
        self._text = text
        self.title = title
        self.placeHolder = placeHolder
    }
    var body: some View {
        ZStack(alignment: .leading) {
            TextField("", text: $text).padding(.leading)
                .frame(height: 60).focused($isTyping)
                .background(isTyping ? .main : Color.white,
                            in: RoundedRectangle(cornerRadius: 12).stroke(style: StrokeStyle(lineWidth: 2)))
            Text(isTyping || !text.isEmpty ? title : placeHolder).padding(.horizontal, 10)
                .background(.screenBackground.opacity(isTyping || !text.isEmpty ? 1 : 0))
                .foregroundStyle(isTyping ? .main : Color.gray)
                .padding(.leading).offset(y: isTyping || !text.isEmpty ? -27 : 0)
                .onTapGesture { isTyping.toggle() }
        }
        .animation(.linear(duration: 0.2), value: isTyping)
    }
}

/*
struct PenculaPlainTextFieldPreviews: PreviewProvider {
    static var previews: some View {
        Group {
            // Empty state preview
            PenculaPlainTextField(text: .constant("text"), title: "titlaaaaaaaae")
                .previewDisplayName("Empty TextField")
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}*/
