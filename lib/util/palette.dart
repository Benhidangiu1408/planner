/// Colors (ARGB) used for blocks, goals, routines and habits.
///
/// Pink and blue lead because they're the app's main colors. The order
/// matters: neighbours stay distinguishable for color-blind readers (checked
/// with an OKLab ΔE validator in light and dark mode). Charts never rely on
/// color alone; every bar is labelled.
const plannerColors = <int>[
  pink,
  blue,
  0xFFBF8600, // amber
  0xFF9B59D0, // purple
  0xFF2BA36B, // green
  0xFFE0712C, // orange
  0xFF1FA2B8, // teal
  0xFFE5534B, // red
  0xFF6B7A8F, // slate: a deliberately neutral choice for admin/misc
];

const pink = 0xFFD9488F;
const blue = 0xFF3D7CE8;

/// The default app accent: pink as the main color with blue alongside.
const defaultAccent = pink;

/// Accents that come with a second hue (used for secondary and tertiary
/// colors) instead of tones derived from the same hue.
const accentPartners = <int, int>{pink: blue};

/// Accent used before pink & blue became the default (for migration).
const legacyDefaultAccent = 0xFF4F6BED;
