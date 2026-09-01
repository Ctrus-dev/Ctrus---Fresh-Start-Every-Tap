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
    "Peel back the moment like an orange and taste it fully",
    "Limit distractions, let your potential ripen like an orange",
    "Your attention decides which grove you grow in",
    "Protect your mental zest",
    "Stay on your branch, like a lime waiting to ripen",
    "Discipline is the zest that flavors freedom",
    "Great work needs a full glass of lemonade",
    "Leftover pulp from distraction dilutes your juice",
    "Protect your grove, protect your time",
  ]

  // Get a random message from the collection
  static func getRandomMessage() -> String {
    return messages.randomElement() ?? "Protect your grove, protect your time"
  }
}
