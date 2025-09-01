enum ContentElement {
    case heading(text: String)
    case heading2(text: String)
    case heading3(text: String)
    case paragraph(text: String)
    case image(src: String, alt: String?)
    case lineBreak
}
