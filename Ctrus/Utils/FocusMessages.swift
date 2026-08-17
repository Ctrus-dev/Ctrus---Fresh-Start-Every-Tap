struct FocusMessages {
  // Collection of inspirational focus messages
  static let messages = [
    "One task at a time",
    "Progress happens one step at a time",
    "Deep work yields great results",
    "Flow state activated",
    "Your attention is precious",
    "Distractions cost more than time",
    "Make each minute matter",
    "Be where your feet are",
    "Dedicate this time to growth",
    "Invest your attention wisely",
    "Concentrate on what matters most",
    "This moment shapes your future",
    "Attention is your greatest asset",
    "Embrace the power of now",
    "Protect your attention",
    "Single-tasking is the new superpower",
    "Limit distractions, unleash potential",
    "Your attention determines your direction",
    "Protect your mental space",
    "Stay on your path",
    "Discipline creates freedom",
    "Be intentional with your time",
    "Quality attention yields quality results",
    "Be present in this moment",
    "Attention management is self-leadership",
    "Deep work creates deep value",
    "Great work requires deep attention",
    "Attention residue diminishes quality",
    "Your mind goes where your attention flows",
    "Each distraction delays your destination",
    "Deep concentration unlocks insights",
    "Attention management is self-care",
    "This moment deserves your full attention",
    "Quality attention produces quality thinking",
    "Mindful attention leads to mindful action",
    "Protect your attention bandwidth",
    "Concentration creates innovation",
    "Attention determines direction",
    "Depth requires protected attention",
    "Immersion leads to insights",
    "Protect your mind, protect your time",
    "Deep work creates lasting value",
  ]

  // Get a random message from the collection
  static func getRandomMessage() -> String {
    return messages.randomElement() ?? "One task at a time"
  }
}
