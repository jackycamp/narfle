enum ContentElement {
    case heading(text: String)
    case paragraph(text: String)
    case image(src: String, alt: String?)
    case lineBreak
}
