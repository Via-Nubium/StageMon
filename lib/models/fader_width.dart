/// How wide a resizable fader column may be, in logical pixels.
///
/// One definition for the two places that have to agree: the pinch that
/// produces a width, and the stored layout that reads one back. A layout
/// file is shared and hand-editable, so what comes out of it gets the same
/// bounds the gesture would have applied.
library;

const double kDefaultFaderWidth = 90;
const double kMinFaderWidth = 60;
const double kMaxFaderWidth = 140;

double clampFaderWidth(num width) =>
    width.toDouble().clamp(kMinFaderWidth, kMaxFaderWidth);
