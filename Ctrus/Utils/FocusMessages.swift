struct FocusMessages {
  // Collection of inspirational focus messages
  static let messages = [
    "When life gives you lemons, make lemonade",
    "An orange grove isn't planted in a day",
    "Let your effort bear fruit",
    "Don't cry over squeezed lemons",
    "The lime always looks greener on someone else's tree",
    "Progress ripens like citrus, one day at a time",
    "This moment shapes the citrus you'll harvest tomorrow",
    "Your attention decides which grove you grow in",
    "Stay on your branch, like a lime waiting to ripen",
    "Great work needs a glass of lemonade",
    "Leftover pulp from distraction dilutes your juice",
    "Protect your grove, protect your time",
  ]

  // Get a random message from the collection
  static func getRandomMessage() -> String {
    return messages.randomElement() ?? "Protect your grove, protect your time"
  }
}
